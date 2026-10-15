require_relative "../test_helper"

#
# Tests for the start/stop follower.
#
# The adapter is stubbed, so these run without dcommsctl. What matters here is what the job reports
# and when it stops: it waits on the JOB (never polling the instance list, which shells out to
# docker compose for every instance), it reads the state exactly once at the end, and it always
# leaves the page in a state the user can act from.
#
class AppStateJobTest < ActiveSupport::TestCase
  # A scripted adapter: one status per poll (the last repeating), and a scripted `inst/list`.
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

    # The start half of a restart. The job issues it after the stop reports terminal; the id it
    # returns is then waited on like any other job.
    def start(id:)
      @start_calls += 1
      "start-job-1"
    end

    def apps_installed_list
      @list_calls += 1
      still = @installed[@list_calls - 1]
      still = @installed.last if still.nil?
      return [] unless still

      [ Dcomms::AppInstance.new(id: "peertube-zebu", catalog_entry_id: "peertube", status: "running") ]
    end
  end

  # Run the job with the poll interval squashed so tests do not sleep. `deadline:` starts the job
  # already past its limit. The broadcasts are captured as decoded partial locals.
  def run_job(adapter, job_id: "start-job-1", instance_id: "peertube-zebu", command: nil, deadline: nil)
    job = AppStateJob.new
    job.define_singleton_method(:adapter) { adapter }
    job.define_singleton_method(:sleep) { |_| }
    job.define_singleton_method(:deadline_for_testing) { deadline } if deadline
    broadcasts = []
    job.define_singleton_method(:stream_replace_to) do |stream, target:, partial:, locals:|
      broadcasts << [ stream, target, partial, locals ]
    end
    job.perform(job_id, instance_id, command)
    broadcasts
  end

  def targets(broadcasts) = broadcasts.map { |_, target, _, _| target }

  # Found by target rather than by position: the job sends the box and the card, and which of the
  # two a test cares about should not depend on the order they happen to be broadcast in.
  def box(broadcasts) = broadcasts.find { |_, target, _, _| target.start_with?("app-box-") }
  def card(broadcasts) = broadcasts.find { |_, target, _, _| target.start_with?("app-card-") }

  ##
  ## waiting
  ##

  test "it polls the job until it is terminal" do
    adapter = FakeAdapter.new(statuses: [ { state: "running" }, { state: "running" }, { state: "done" } ])

    run_job(adapter)

    assert_equal 3, adapter.status_calls
  end

  test "it reads the instance list exactly once, after the job is done" do
    # `inst/list` shells out to `docker compose ps` for EVERY instance (5s timeout each), so it is
    # the expensive call and the one thing this job must not do in a loop.
    adapter = FakeAdapter.new(statuses: [ { state: "running" }, { state: "done" } ])

    run_job(adapter)

    assert_equal 1, adapter.list_calls
  end

  test "it gives up after the maximum duration" do
    adapter = FakeAdapter.new(statuses: [ { state: "running" } ])

    broadcasts = run_job(adapter, deadline: 1.second.ago)

    assert_equal 1, adapter.list_calls, "the state is still reported once, so the page is not stuck"
    assert_equal "apps/box", box(broadcasts)[2]
    assert_match(/stopped waiting/, box(broadcasts)[3][:message])
  end

  ##
  ## reporting
  ##

  test "a finished command reports the instance's new state" do
    adapter = FakeAdapter.new(statuses: [ { state: "done" } ])

    broadcasts = run_job(adapter)

    assert_equal "apps/box", broadcasts.first[2]
    assert_equal "peertube-zebu", broadcasts.first[3][:app].id
    # No message: the box re-renders from the state, which is the report.
    assert_nil broadcasts.first[3][:message]
  end

  test "a failed command carries the daemon's error" do
    adapter = FakeAdapter.new(statuses: [ { state: "failed", error: "compose up exited 1" } ])

    broadcasts = run_job(adapter)

    assert_equal "compose up exited 1", broadcasts.first[3][:message]
  end

  test "a failed command still reports the state" do
    # The command failing does not mean the instance is unchanged, and the page has to stop showing
    # the in-flight spinner either way.
    adapter = FakeAdapter.new(statuses: [ { state: "failed", error: "boom" } ])

    broadcasts = run_job(adapter)

    assert_equal 1, adapter.list_calls
    assert_equal "apps/box", broadcasts.first[2]
  end

  test "it broadcasts to the instance's stream and to the index" do
    adapter = FakeAdapter.new(statuses: [ { state: "done" } ])

    broadcasts = run_job(adapter)

    assert_equal [ "peertube-zebu", "apps" ], broadcasts.map(&:first)
    assert_equal [ "app-box-peertube-zebu", "app-card-peertube-zebu" ], targets(broadcasts)
    assert_equal [ "apps/box", "apps/card" ], broadcasts.map { |_, _, partial, _| partial }
  end

  test "a job the daemon no longer knows still reports the state" do
    # `job/status` raising means the daemon restarted or dropped the job. Waiting forever would
    # wedge the page; the state it can still read is the honest thing to report.
    adapter = FakeAdapter.new(statuses: [ :unknown ])

    broadcasts = run_job(adapter)

    assert_equal 1, adapter.status_calls
    assert_equal "apps/box", broadcasts.first[2]
  end

  test "an unreachable daemon reports the reason" do
    adapter = Class.new do
      def job_status(id:) = raise(DcommsClient::ConnectionError, "no route to host")

      def apps_installed_list = [ Dcomms::AppInstance.new(id: "peertube-zebu", status: "running") ]
    end.new

    broadcasts = run_job(adapter)

    # The state could still be read, so the box renders and carries the reason.
    assert_equal "apps/box", box(broadcasts)[2]
    assert_match(/no route to host/, box(broadcasts)[3][:message])
  end

  test "a state read that fails replaces the box with the reason" do
    # The daemon went away between the job ending and the state being read. There is no box to
    # render, and the buttons must not be left spinning (a rescue body is not covered by its own
    # rescue, which is how this used to escape the job entirely).
    adapter = Class.new do
      def job_status(id:) = Dcomms::JobStatus.new(id: id, state: "done")

      def apps_installed_list = raise(DcommsClient::ConnectionError, "no route to host")
    end.new

    broadcasts = run_job(adapter)

    assert_equal [ "app-box-peertube-zebu" ], targets(broadcasts)
    assert_equal "apps/box_message", broadcasts.first[2]
    assert_match(/no route to host/, broadcasts.first[3][:message])
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
    assert_equal "apps/box", box(broadcasts)[2]
    assert_nil box(broadcasts)[3][:message]
  end

  test "a failed stop does not issue the start half" do
    # Starting on top of a container the stop could not bring down would either be refused by the
    # lock or leave two of them racing.
    adapter = FakeAdapter.new(statuses: [ { state: "failed", error: "compose down exited 1" } ])

    broadcasts = run_job(adapter, command: "restart")

    assert_equal 0, adapter.start_calls
    assert_equal "compose down exited 1", box(broadcasts)[3][:message]
  end

  test "a restart whose start half fails reports the start's error" do
    # The stop succeeded, so the instance is down: the start's failure is the fact that matters.
    adapter = FakeAdapter.new(statuses: [ { state: "done" }, { state: "failed", error: "compose up exited 1" } ])

    broadcasts = run_job(adapter, command: "restart")

    assert_equal 1, adapter.start_calls
    assert_equal "compose up exited 1", box(broadcasts)[3][:message]
  end

  test "a restart that cannot issue its start half reports why" do
    adapter = Class.new do
      def initialize = @calls = 0

      def job_status(id:)
        @calls += 1
        Dcomms::JobStatus.new(id: id, state: "done")
      end

      def start(id:) = raise(DcommsClient::JobInProgress.new(code: -32603, message: "The job is in progress"))

      def apps_installed_list = [ Dcomms::AppInstance.new(id: "peertube-zebu", status: "stopped") ]
    end.new

    broadcasts = run_job(adapter, command: "restart")

    assert_equal "apps/box", box(broadcasts)[2]
    assert_match(/job is in progress/, box(broadcasts)[3][:message])
  end

  test "a plain start does not issue a second start" do
    # The command name defaults to a plain command, so the pre-restart behaviour is unchanged.
    adapter = FakeAdapter.new(statuses: [ { state: "done" } ])

    broadcasts = run_job(adapter, command: "start")

    assert_equal 0, adapter.start_calls
    assert_equal "apps/box", box(broadcasts)[2]
  end

  ##
  ## the instance is gone
  ##

  test "an instance that vanished while the command ran is reported as gone" do
    # Someone uninstalled it concurrently. There is no box to render, but the buttons must not spin
    # forever, so the box is replaced with a message that keeps the target id.
    adapter = FakeAdapter.new(statuses: [ { state: "done" } ], installed: [ false ])

    broadcasts = run_job(adapter)

    assert_equal [ "app-box-peertube-zebu" ], targets(broadcasts)
    assert_equal "apps/box_message", broadcasts.first[2]
    assert_match(/no longer reported/, broadcasts.first[3][:message])
  end

  test "a failed command on a vanished instance reports the failure, not the absence" do
    # The command's own error is the more useful of the two facts.
    adapter = FakeAdapter.new(statuses: [ { state: "failed", error: "compose up exited 1" } ],
                              installed: [ false ])

    broadcasts = run_job(adapter)

    assert_equal "compose up exited 1", broadcasts.first[3][:message]
  end

  test "the index card is not touched when the instance is gone" do
    adapter = FakeAdapter.new(statuses: [ { state: "done" } ], installed: [ false ])

    broadcasts = run_job(adapter)

    assert_equal [ "peertube-zebu" ], broadcasts.map(&:first)
  end
end
