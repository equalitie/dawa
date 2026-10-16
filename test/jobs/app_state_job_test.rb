require_relative "../test_helper"

#
# Tests for the start/stop/restart follower.
#
# The adapter is stubbed, so these run without dcommsctl. What matters here is what the job does and
# when it stops: it waits on the JOB (never polling the instance list, which shells out to
# docker compose for every instance), it re-reads the instance once at the end, and it always leaves
# the page in a state the user can act from.
#
class AppStateJobTest < ActiveSupport::TestCase
  # A scripted adapter: one status per poll (the last repeating), and a scripted `inst/list`.
  #
  # `job_status` is the only call the wait loop makes; `apps_installed_list` is read when the job
  # resolves the instance, which is once per broadcast that needs it (AppBaseJob#app memoizes).
  class FakeAdapter
    attr_reader :status_calls, :list_calls, :start_calls

    def initialize(statuses:, installed: [ true ])
      @statuses = statuses
      @installed = installed
      @status_calls = 0
      @list_calls = 0
      @start_calls = 0
    end

    def job_status(id:)
      @status_calls += 1
      spec = @statuses[@status_calls - 1] || @statuses.last
      raise DcommsClient::EmptyResult, "unknown job #{id}" if spec == :unknown

      Dcomms::JobStatus.new(**{ id: id, state: "running" }.merge(spec))
    end

    # The start half of a restart. Issued after the stop reports terminal.
    def start(id:)
      @start_calls += 1
      "start-job-1"
    end

    def job_list(instance_id: nil, active_only: false)
      []
    end

    def apps_installed_list
      @list_calls += 1
      still = @installed[@list_calls - 1]
      still = @installed.last if still.nil?
      return [] unless still

      [ Dcomms::AppInstance.new(id: "peertube-zebu", catalog_entry_id: "peertube", status: "running") ]
    end
  end

  #
  # Run the job with the poll interval (and the restart pause) squashed so tests do not sleep.
  #
  # The broadcast helpers are stubbed at the AppBaseJob level: this suite is about WHICH broadcasts
  # the job decides to send, so recording the calls is the assertion surface. What each one renders
  # is the view's business and is covered by the controller tests.
  #
  def run_job(adapter, job_id: "start-job-1", app_id: "peertube-zebu", command: nil, deadline: nil)
    job = AppStateJob.new
    job.define_singleton_method(:adapter) { adapter }
    job.define_singleton_method(:sleep) { |_| }
    job.define_singleton_method(:deadline_for_testing) { deadline } if deadline

    broadcasts = []
    %i[broadcast_job_list broadcast_job_row broadcast_app_box broadcast_app_card].each do |name|
      job.define_singleton_method(name) do |**kwargs|
        broadcasts << [ name, kwargs ]
      end
    end

    job.perform(job_id: job_id, app_id: app_id, command: command)
    broadcasts
  end

  def broadcasts_named(broadcasts, name) = broadcasts.select { |n, _| n == name }
  def first_of(broadcasts, name) = broadcasts_named(broadcasts, name).first

  ##
  ## waiting
  ##

  test "it polls the job until it is terminal" do
    adapter = FakeAdapter.new(statuses: [ { state: "running" }, { state: "running" }, { state: "done" } ])

    run_job(adapter)

    assert_equal 3, adapter.status_calls
  end

  test "it gives up after the maximum duration" do
    adapter = FakeAdapter.new(statuses: [ { state: "running" } ])

    broadcasts = run_job(adapter, deadline: 1.second.ago)

    assert_equal I18n.t("apps.state.timeout"), first_of(broadcasts, :broadcast_app_box)[1][:message]
  end

  ##
  ## reporting
  ##

  test "a finished command refreshes the box, the card and the job row" do
    adapter = FakeAdapter.new(statuses: [ { state: "done" } ])

    broadcasts = run_job(adapter)

    assert_equal %i[broadcast_job_list broadcast_app_box broadcast_app_card broadcast_job_row],
      broadcasts.map(&:first)
    # No message: the box re-renders from the state, which is the report.
    assert_nil first_of(broadcasts, :broadcast_app_box)[1][:message]
  end

  test "a failed command carries the daemon's error" do
    adapter = FakeAdapter.new(statuses: [ { state: "failed", error: "compose up exited 1" } ])

    broadcasts = run_job(adapter)

    assert_equal "compose up exited 1", first_of(broadcasts, :broadcast_app_box)[1][:message]
  end

  test "a job the daemon no longer knows still reports the state" do
    # `job/status` raising means the daemon restarted or dropped the job. Waiting forever would
    # wedge the page; the state it can still read is the honest thing to report.
    #
    # Two reads: the wait loop's (which raises and ends the wait), then `AppBaseJob#job`'s, which
    # tries again to render the job row -- the row needs a job, and this is the last chance to get
    # one. The daemon not knowing it is answered as nil by `wait_for_dcomms_job`.
    adapter = FakeAdapter.new(statuses: [ :unknown ])

    broadcasts = run_job(adapter)

    assert_equal 2, adapter.status_calls
    refute_nil first_of(broadcasts, :broadcast_app_box)
  end

  test "an unreachable daemon reports the reason" do
    adapter = Class.new do
      def job_status(id:) = raise(DcommsClient::ConnectionError, "no route to host")

      def apps_installed_list = [ Dcomms::AppInstance.new(id: "peertube-zebu", status: "running") ]
    end.new

    broadcasts = run_job(adapter)

    assert_match(/no route to host/, first_of(broadcasts, :broadcast_app_box)[1][:message])
  end

  ##
  ## restart (a stop followed by a start)
  ##

  test "a restart issues the start half only after the stop is terminal" do
    adapter = FakeAdapter.new(statuses: [ { state: "running" }, { state: "done" } ])

    broadcasts = run_job(adapter, command: "restart")

    # Two polls for the stop (running, then done) and one for the start job, which the last
    # repeating status reports done.
    assert_equal 3, adapter.status_calls
    assert_equal 1, adapter.start_calls
    assert_nil first_of(broadcasts, :broadcast_app_box)[1][:message]
  end

  test "a failed stop does not issue the start half" do
    # Starting on top of a container the stop could not bring down would either be refused by the
    # lock or leave two of them racing.
    adapter = FakeAdapter.new(statuses: [ { state: "failed", error: "compose down exited 1" } ])

    broadcasts = run_job(adapter, command: "restart")

    assert_equal 0, adapter.start_calls
    assert_equal "compose down exited 1", first_of(broadcasts, :broadcast_app_box)[1][:message]
  end

  test "a restart whose start half fails reports the start's error" do
    # The stop succeeded, so the instance is down: the start's failure is the fact that matters.
    adapter = FakeAdapter.new(statuses: [ { state: "done" }, { state: "failed", error: "compose up exited 1" } ])

    broadcasts = run_job(adapter, command: "restart")

    assert_equal 1, adapter.start_calls
    assert_equal "compose up exited 1", first_of(broadcasts, :broadcast_app_box)[1][:message]
  end

  test "a restart that cannot issue its start half reports why" do
    adapter = Class.new do
      def job_status(id:) = Dcomms::JobStatus.new(id: id, state: "done")

      def start(id:) = raise(DcommsClient::JobInProgress.new(code: -32603, message: "The job is in progress"))

      def apps_installed_list = [ Dcomms::AppInstance.new(id: "peertube-zebu", status: "stopped") ]
    end.new

    broadcasts = run_job(adapter, command: "restart")

    assert_match(/job is in progress/, first_of(broadcasts, :broadcast_app_box)[1][:message])
  end

  test "a plain start does not issue a second start" do
    adapter = FakeAdapter.new(statuses: [ { state: "done" } ])

    broadcasts = run_job(adapter, command: "start")

    assert_equal 0, adapter.start_calls
    refute_nil first_of(broadcasts, :broadcast_app_box)
  end

  ##
  ## job list refresh
  ##

  test "the job list is refreshed when the command starts, before the wait" do
    # The row has to appear as in-flight immediately; waiting for the terminal state would leave the
    # page showing nothing while the command runs.
    adapter = FakeAdapter.new(statuses: [ { state: "done" } ])

    broadcasts = run_job(adapter)

    assert_equal :broadcast_job_list, broadcasts.first.first
  end

  test "a restart refreshes the job list again for the start half" do
    # The stop and the start are two separate jobs, so the list is stale after the stop.
    adapter = FakeAdapter.new(statuses: [ { state: "done" } ])

    broadcasts = run_job(adapter, command: "restart")

    assert_equal 2, broadcasts_named(broadcasts, :broadcast_job_list).size
  end

  ##
  ## the instance is gone
  ##

  test "an instance that vanished while the command ran is reported as gone" do
    # Someone uninstalled it concurrently. There is no box to render from an app, so the reason goes
    # in the box's place and the card is not touched.
    adapter = FakeAdapter.new(statuses: [ { state: "done" } ], installed: [ false ])

    broadcasts = run_job(adapter)

    assert_equal [ :broadcast_job_list, :broadcast_app_box ], broadcasts.map(&:first)
    assert_match(/no longer reported/, first_of(broadcasts, :broadcast_app_box)[1][:message])
    assert_nil first_of(broadcasts, :broadcast_app_box)[1][:app]
  end

  test "a failed command on a vanished instance reports the failure, not the absence" do
    # The command's own error is the more useful of the two facts.
    adapter = FakeAdapter.new(statuses: [ { state: "failed", error: "compose up exited 1" } ],
                              installed: [ false ])

    broadcasts = run_job(adapter)

    assert_equal "compose up exited 1", first_of(broadcasts, :broadcast_app_box)[1][:message]
  end

  test "the index card is not touched when the instance is gone" do
    adapter = FakeAdapter.new(statuses: [ { state: "done" } ], installed: [ false ])

    broadcasts = run_job(adapter)

    assert_empty broadcasts_named(broadcasts, :broadcast_app_card)
  end
end
