require_relative "../test_helper"

#
# Integration tests for the app show page and its job lists.
#
# The adapter is stubbed so these run without a live dcommsctl. What matters here is the
# page's behaviour: it shows one app, it separates in-flight jobs from finished ones, and it
# never offers a log link for a job whose log the daemon cannot serve.
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

  def get_show(id = "peertube-zebu")
    login_as(@user)
    get app_path(id)
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

  test "in-flight and finished jobs are listed separately" do
    jobs = {
      "peertube-zebu" => [
        job(id: "install-1", state: "running"),
        job(id: "install-0", state: "done", finished_at: "2026-09-16T10:01:00Z", exit_code: 0)
      ]
    }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "h4", text: "Active Jobs"
      assert_select "h4", text: "Past Jobs"
      assert_select "tbody tr", count: 2
      # the running job is in the active list, the done one in the past list
      assert_select "tr[data-job-id='install-1'] .badge", text: "Running"
      assert_select "tr[data-job-id='install-0'] .badge", text: "Done"
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
      assert_select "tr[data-job-id='mine']", count: 1
      assert_select "tr[data-job-id='theirs']", count: 0
    end
  end

  test "an app with no jobs explains both lists" do
    with_stubbed_adapter(apps: [ instance_ ], jobs: { "peertube-zebu" => [] }) do
      get_show

      assert_response :success
      assert_select "body", text: /No jobs are running for this app/
      assert_select "body", text: /No jobs have been run for this app yet/
    end
  end

  test "an app with only past jobs does not claim any are running" do
    jobs = { "peertube-zebu" => [ job(state: "done", finished_at: "2026-09-16T10:01:00Z") ] }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "body", text: /No jobs are running for this app/
      assert_select "tbody tr", count: 1
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

  test "a finished job offers no log link" do
    # The daemon cannot serve a finished job's log (it renames the file but keeps the old
    # path), so a link here could only ever error. Regression guard for that rule.
    jobs = { "peertube-zebu" => [ job(id: "install-0", state: "done", finished_at: "2026-09-16T10:01:00Z") ] }

    with_stubbed_adapter(apps: [ instance_ ], jobs: jobs) do
      get_show

      assert_response :success
      assert_select "a[href=?]", app_job_path("peertube-zebu", "install-0"), count: 0
      assert_select "tr[data-job-id='install-0']", text: /Not available/
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
end
