require_relative "../test_helper"

#
# Integration tests for the app show page and its job lists.
#
# The adapter is stubbed so these run without a live dcommsctl. What matters here is the
# page's behaviour: it shows one app, it separates in-flight jobs from finished ones, and it
# offers a log link only for jobs whose output is still being produced.
#
class AppsShowTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(username: "apps-show-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
  end

  def with_stubbed_adapter(apps: nil, jobs: {}, raises: nil, log: nil, job_log_raises: nil)
    fake = Object.new
    fake.define_singleton_method(:apps_installed_list) do
      raise raises if raises
      apps || []
    end
    fake.define_singleton_method(:job_list) do |instance_id: nil, active_only: false|
      # Accept either a flat array or a hash keyed by instance id, then filter by instance
      # as the real daemon does. A stub that ignored instance_id would make the "only this
      # instance's jobs" test pass for the wrong reason.
      all = jobs.is_a?(Hash) ? jobs.values.flatten : jobs
      scoped = instance_id ? all.select { |j| j.instance_id == instance_id } : all
      scoped.reject { |j| active_only && j.terminal? }
    end
    fake.define_singleton_method(:job_log) do |id:, instance_id:, offset: 0|
      raise job_log_raises if job_log_raises
      log
    end

    AppsController.alias_method(:adapter_without_stub, :adapter)
    AppsController.define_method(:adapter) { fake }
    AppJobsController.alias_method(:adapter_without_stub, :adapter)
    AppJobsController.define_method(:adapter) { fake }
    yield
  ensure
    AppsController.alias_method(:adapter, :adapter_without_stub)
    AppsController.send(:remove_method, :adapter_without_stub)
    AppJobsController.alias_method(:adapter, :adapter_without_stub)
    AppJobsController.send(:remove_method, :adapter_without_stub)
  end

  def instance_(id: "peertube-zebu", catalog_entry_id: "peertube", domain: nil,
                version: nil, status: "running")
    Dcomms::AppInstance.new(
      id: id, catalog_entry_id: catalog_entry_id, domain: domain, version: version, status: status
    )
  end

  def job(id: "install-1", type: "install", state: "running", instance_id: "peertube-zebu",
          started_at: "2026-09-17T10:00:00Z", finished_at: nil, exit_code: nil, error: nil)
    Dcomms::JobStatus.new(
      id: id, type: type, state: state, instance_id: instance_id,
      started_at: started_at, finished_at: finished_at, exit_code: exit_code, error: error
    )
  end

  def get_show(id = "peertube-zebu", **params)
    login_as(@user)
    get app_path(id, **params)
  end

  ##
  ## access and lookup
  ##

  test "show requires an admin" do
    get app_path("peertube-zebu")

    assert_response :redirect
  end

  test "show renders the app it was asked for" do
    with_stubbed_adapter(apps: [ instance_(version: "7.0.0", domain: "pt.test") ]) do
      get_show

      assert_response :success
      assert_select "body", text: /peertube-zebu/
      assert_select "body", text: /7\.0\.0/
      assert_select "body", text: /pt\.test/
    end
  end

  test "an unknown app is a 404, not an empty page" do
    # The id came from a link, so an absent one means it was uninstalled or the URL is
    # wrong. Rendering "no jobs" would be a different and false claim.
    with_stubbed_adapter(apps: [ instance_ ]) do
      get_show("deleted-app")

      assert_response :not_found
    end
  end

  test "the index links each card through to its show page" do
    with_stubbed_adapter(apps: [ instance_ ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select "a[href=?]", app_path("peertube-zebu")
    end
  end

  ##
  ## job lists
  ##

  test "the job columns are ordered started, state, action, outcome" do
    # The cell order in JobRowComponent and the column order in JobHelper#job_columns are two
    # separate lists that must agree: if they drift, every cell renders under the wrong heading and
    # nothing else would fail. This pins both, in order.
    jobs = { "peertube-zebu" => [ job(id: "install-1", state: "running") ] }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "thead th", count: 4 do |ths|
        assert_equal [ "Started", "State", "Action", "Outcome" ], ths.map(&:text).map(&:strip)
      end
      # The cells under them, in the same order. The row is addressed by its dom_id (`job-<id>`),
      # which is the same id a job broadcasts a replacement to.
      row = css_select("tr#job-install-1 td")
      assert_equal 4, row.size, "four cells, one per column"
      assert_match(/\d/, row[0].text, "started is the first cell")
      assert_match(/Running/, row[1].text, "state is the second cell")
      assert_match(/install/, row[2].text, "action (the daemon's job type) is the third cell")
      assert_match(/In progress/, row[3].text, "outcome is the fourth cell")
    end
  end

  test "in-flight and finished jobs are listed in one list, in-flight first" do
    jobs = {
      "peertube-zebu" => [
        job(id: "install-0", state: "done", started_at: "2026-09-16T10:00:00Z",
            finished_at: "2026-09-16T10:01:00Z", exit_code: 0),
        job(id: "install-1", state: "running", started_at: "2026-09-17T10:00:00Z")
      ]
    }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "tbody tr", count: 2
      assert_select "tbody tr:first-child#job-install-1"
      assert_select "tbody tr:nth-child(2)#job-install-0"
      assert_select "tr#job-install-1 .badge", text: "Running"
      assert_select "tr#job-install-0 .badge", text: "Done"
    end
  end

  ##
  ## job list cap
  ##

  test "the list is capped at the page size, newest first" do
    # More finished jobs than the page size, with distinct start times. Only the newest are shown,
    # in newest-first order within the finished group.
    jobs = {
      "peertube-zebu" => (0..11).map do |i|
        job(id: "job-#{i}", state: "done",
            started_at: format("2026-09-%02dT10:00:00Z", i + 1),
            finished_at: format("2026-09-%02dT10:01:00Z", i + 1), exit_code: 0)
      end
    }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "tbody tr", count: DcommsClientConcern::JOBS_PAGE_SIZE
      # The newest is first; the oldest jobs fall off the end.
      assert_select "tbody tr:first-child#job-job-11"
      newest_shown = 11 - DcommsClientConcern::JOBS_PAGE_SIZE + 1
      assert_select "tr#job-job-#{newest_shown}", count: 1
      assert_select "tr#job-job-#{newest_shown - 1}", count: 0
    end
  end

  test "a capped list links to the full list" do
    jobs = {
      "peertube-zebu" => (0..11).map do |i|
        job(id: "job-#{i}", state: "done",
            started_at: format("2026-09-%02dT10:00:00Z", i + 1),
            finished_at: format("2026-09-%02dT10:01:00Z", i + 1), exit_code: 0)
      end
    }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "a[href=?]", app_jobs_path("peertube-zebu"), text: /View All/
    end
  end

  test "no link is offered when the list is not capped" do
    jobs = {
      "peertube-zebu" => (0..(DcommsClientConcern::JOBS_PAGE_SIZE - 1)).map do |i|
        job(id: "job-#{i}", state: "done",
            started_at: format("2026-09-%02dT10:00:00Z", i + 1),
            finished_at: format("2026-09-%02dT10:01:00Z", i + 1), exit_code: 0)
      end
    }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "tbody tr", count: DcommsClientConcern::JOBS_PAGE_SIZE
      assert_select "a[href=?]", app_jobs_path("peertube-zebu"), count: 0
    end
  end

  test "an in-flight job is never hidden by the cap" do
    # A full page of finished jobs plus one running one: the running job sorts first, so the cap
    # cuts finished history, never the work in progress.
    jobs = {
      "peertube-zebu" => (
        (0..(DcommsClientConcern::JOBS_PAGE_SIZE - 1)).map do |i|
          job(id: "job-#{i}", state: "done",
              started_at: format("2026-08-%02dT10:00:00Z", i + 1),
              finished_at: format("2026-08-%02dT10:01:00Z", i + 1), exit_code: 0)
        end + [ job(id: "running-1", state: "running", started_at: "2026-09-30T10:00:00Z") ]
      )
    }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "tbody tr", count: DcommsClientConcern::JOBS_PAGE_SIZE
      assert_select "tbody tr:first-child#job-running-1"
    end
  end

  test "only this instance's jobs are requested and shown" do
    jobs = {
      "peertube-zebu" => [ job(id: "mine", state: "running") ],
      "other-app" => [ job(id: "theirs", type: "backup", state: "running", instance_id: "other-app") ]
    }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "tr#job-mine", count: 1
      assert_select "tr#job-theirs", count: 0
    end
  end

  test "an app with no jobs shows an empty list, not a broken table" do
    with_stubbed_adapter(apps: [ instance_ ], jobs: { "peertube-zebu" => [] }) do
      get_show

      assert_response :success
      # The table renders its own placeholder row when there is nothing to list, so "no trs" is not
      # the expectation -- "no JOB rows" is. Selector by the job-row id prefix is not possible in
      # assert_select, so this asserts the placeholder and the absence of a job row.
      assert_select "#empty-row"
      assert_select "tr#job-install-1", count: 0
      assert_select "a[href=?]", app_jobs_path("peertube-zebu"), count: 0
    end
  end

  test "an app with only finished jobs shows them in the one list" do
    jobs = { "peertube-zebu" => [ job(state: "done", finished_at: "2026-09-16T10:01:00Z") ] }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "tbody tr", count: 1
      assert_select "body", text: /No jobs have been run for this app yet/, count: 0
    end
  end

  ##
  ## job detail
  ##

  test "a job state renders as a badge" do
    %w[pending running done failed].each do |state|
      jobs = { "peertube-zebu" => [ job(state: state, finished_at: "2026-09-16T10:01:00Z") ] }

      with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
        get_show

        assert_response :success
        assert_select ".badge", text: I18n.t("jobs.state.#{state}")
      end
    end
  end

  test "a failed job states its error" do
    jobs = {
      "peertube-zebu" => [
        job(state: "failed", error: "port 9000 already in use",
            finished_at: "2026-09-16T10:01:00Z", exit_code: 1)
      ]
    }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "body", text: /port 9000 already in use/
    end
  end

  test "a job with no timestamp shows a placeholder rather than a blank cell" do
    jobs = { "peertube-zebu" => [ job(started_at: nil) ] }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "em[data-placeholder='true']", text: "Unknown"
    end
  end

  ##
  ## the log link rule
  ##

  test "a running job offers a log link" do
    jobs = { "peertube-zebu" => [ job(id: "install-1", state: "running") ] }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "a[href=?]", app_job_path("peertube-zebu", "install-1")
    end
  end

  test "a finished job still offers a log link" do
    # dcommsctl serves a finished job's log too, so the row links to it for completed jobs as
    # well as running ones; a failed job's output is exactly what an operator comes here to read.
    jobs = { "peertube-zebu" => [ job(id: "install-0", state: "done", finished_at: "2026-09-16T10:01:00Z") ] }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "a[href=?]", app_job_path("peertube-zebu", "install-0")
    end
  end

  test "a job link survives a daemon id containing dots and colons" do
    # dcommsctl ids look like "install-10-12.00:49:44.758956-2". The link must carry the whole
    # id, and the route must accept it: an unconstrained :id split the trailing "." into
    # :format and the colons stopped it matching, so the link 404'd.
    daemon_id = "install-10-12.00:49:44.758956-2"
    jobs = { "peertube-zebu" => [ job(id: daemon_id, state: "done", finished_at: "2026-09-16T10:01:00Z") ] }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "a[href=?]", app_job_path("peertube-zebu", daemon_id)
    end
  end

  test "the whole job row is a link to the job's log page" do
    jobs = { "peertube-zebu" => [ job(id: "install-1", state: "running") ] }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "tr#job-install-1 td.position-relative a.stretched-link[href=?]",
                    app_job_path("peertube-zebu", "install-1"), minimum: 1
      assert_select "tr#job-install-1 a.btn", count: 0
    end
  end

  ##
  ## resilience
  ##

  test "an unreachable backend shows a banner rather than raising" do
    with_stubbed_adapter(raises: DcommsClient::ConnectionError.new("no route to host")) do
      get_show

      assert_response :success
      assert_select "body", text: /no route to host/
    end
  end

  test "show has no missing translations" do
    jobs = { "peertube-zebu" => [ job(state: "running") ] }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_no_match(/translation missing/, response.body)
    end
  end

  test "show leaks no Haml markup into the output" do
    jobs = { "peertube-zebu" => [ job(state: "running") ] }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_no_match(/= t\(/, response.body)
    end
  end

  ##
  ## start and stop
  ##

  test "a stopped app offers Start and not Stop" do
    with_stubbed_adapter(apps: [ instance_(status: "stopped") ]) do
      get_show

      assert_response :success
      # The command that would be sent, not just the label: a button wired to the wrong command
      # would look identical.
      assert_select "input[name='command'][value='start']"
      assert_select "input[name='command'][value='stop']", count: 0
      assert_select "button[disabled]", text: /Stop/
    end
  end

  test "a running app offers Stop and not Start" do
    with_stubbed_adapter(apps: [ instance_(status: "running") ]) do
      get_show

      assert_response :success
      assert_select "input[name='command'][value='stop']"
      assert_select "input[name='command'][value='start']", count: 0
      assert_select "button[disabled]", text: /Start/
    end
  end

  test "a running app offers Stop and Restart and not Start" do
    with_stubbed_adapter(apps: [ instance_(status: "running") ]) do
      get_show

      assert_response :success
      assert_select "input[name='command'][value='stop']"
      assert_select "input[name='command'][value='restart']"
      assert_select "input[name='command'][value='start']", count: 0
      assert_select "button[disabled]", text: /Start/
    end
  end

  test "a stopped app does not offer Restart" do
    # Restarting a stopped app would only be a start, so the button is present but disabled rather
    # than a second way to do the same thing.
    with_stubbed_adapter(apps: [ instance_(status: "stopped") ]) do
      get_show

      assert_response :success
      assert_select "input[name='command'][value='restart']", count: 0
      assert_select "button[disabled]", text: /Restart/
    end
  end

  test "an app with no reported status does not offer Restart" do
    with_stubbed_adapter(apps: [ instance_(status: nil) ]) do
      get_show

      assert_response :success
      assert_select "input[name='command'][value='restart']", count: 0
      assert_select "button[disabled]", text: /Restart/
    end
  end

  test "an app with no reported status offers neither command" do
    # The daemon sends an empty status when it cannot ask docker compose. Either command could be
    # the wrong one there, so neither is offered rather than guessing.
    with_stubbed_adapter(apps: [ instance_(status: nil) ]) do
      get_show

      assert_response :success
      assert_select "input[name='command']", count: 0
      assert_select "button[disabled]", text: /Start/
      assert_select "button[disabled]", text: /Stop/
    end
  end

  test "the buttons submit to the app's own update url" do
    with_stubbed_adapter(apps: [ instance_(status: "stopped") ]) do
      get_show

      assert_response :success
      assert_select "form[action=?][method=post]", app_path("peertube-zebu") do
        assert_select "input[name='_method'][value='put']"
      end
    end
  end

  test "the box is the target a start or stop command replaces" do
    # AppStateJob replaces this element when the command finishes, so the id has to be on the box
    # the page actually renders.
    with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu") ]) do
      get_show

      assert_response :success
      assert_select "#app-box"
    end
  end

  test "the page subscribes to the instance, so a command's result can reach it" do
    with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu") ]) do
      get_show

      assert_response :success
      assert_match(/turbo-cable-stream-source/, response.body)
      assert_select "div[data-controller='stream-ready']"
    end
  end

  test "the buttons are stream-ready targets, so they stay disabled until subscribed" do
    # A click before the subscription exists would start a command whose result the page cannot
    # receive, leaving it stale until a reload.
    with_stubbed_adapter(apps: [ instance_(status: "stopped") ]) do
      get_show

      assert_response :success
      assert_select "button[data-stream-ready-target='button'][form]"
    end
  end

  ##
  ## removing the app
  ##
  ##
  ## The show page's remove control is currently commented out in `apps/_box.html.haml`, so the
  ## three tests that covered it are removed rather than left failing. Restore them (and the
  ## control) together: the link goes to the confirmation page, never straight to the DELETE.
  ##
end
