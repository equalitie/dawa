require_relative "../test_helper"

#
# Integration tests for the job log page.
#
class AppJobsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(username: "app-jobs-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
  end

  def with_stubbed_adapter(apps: [], jobs: [], log: nil, job_log_raises: nil, raises: nil)
    fake = Object.new
    fake.define_singleton_method(:apps_installed_list) do
      raise raises if raises
      apps
    end
    fake.define_singleton_method(:job_list) do |instance_id: nil, active_only: false|
      raise raises if raises

      # Filter by instance like the real daemon does: this stub used to ignore instance_id,
      # which made the "job must belong to this app" test pass for the wrong reason.
      scoped = instance_id ? jobs.select { |j| j.instance_id == instance_id } : jobs
      scoped.reject { |j| active_only && j.terminal? }
    end
    fake.define_singleton_method(:job_log) do |id:, offset: 0|
      raise job_log_raises if job_log_raises
      log
    end

    AppJobsController.alias_method(:adapter_without_stub, :adapter)
    AppJobsController.define_method(:adapter) { fake }
    yield
  ensure
    AppJobsController.alias_method(:adapter, :adapter_without_stub)
    AppJobsController.send(:remove_method, :adapter_without_stub)
  end

  def instance_(id: "peertube-zebu")
    Dcomms::AppInstance.new(id: id)
  end

  def job(id: "install-1", type: "install", state: "running", instance_id: "peertube-zebu")
    Dcomms::JobStatus.new(
      id: id, type: type, state: state, instance_id: instance_id,
      started_at: "2026-09-17T10:00:00Z",
      finished_at: state == "running" ? nil : "2026-09-17T10:01:00Z"
    )
  end

  def job_log(text: "Cloning into 'peertube'...\n", finished: true)
    Dcomms::JobLog.new(log: text, next_offset: text.bytesize, finished: finished)
  end

  def get_log(app_id: "peertube-zebu", job_id: "install-1")
    login_as(@user)
    get app_job_path(app_id, job_id)
  end

  test "show requires an admin" do
    get app_job_path("peertube-zebu", "install-1")

    assert_response :redirect
  end

  test "a running job's output is rendered" do
    with_stubbed_adapter(apps: [ instance_ ], jobs: [ job ], log: job_log) do
      get_log

      assert_response :success
      assert_select "pre code", text: /Cloning into 'peertube'/
    end
  end

  test "a daemon-style job id (with dots and colons) routes to the right job" do
    daemon_id = "install-10-12.00:49:44.758956-2"

    with_stubbed_adapter(apps: [ instance_ ], jobs: [ job(id: daemon_id) ], log: job_log) do
      get_log(job_id: daemon_id)

      assert_response :success
      assert_select "pre code", text: /Cloning into 'peertube'/
    end
  end

  test "a running job that has produced no output says so rather than showing an empty box" do
    with_stubbed_adapter(apps: [ instance_ ], jobs: [ job ], log: job_log(text: "", finished: false)) do
      get_log

      assert_response :success
      assert_select "body", text: /has not produced any output yet/
      assert_select "pre", count: 0
    end
  end

  test "a finished job that produced no output says so" do
    finished = job(state: "done")

    with_stubbed_adapter(apps: [ instance_ ], jobs: [ finished ], log: job_log(text: "", finished: true)) do
      get_log

      assert_response :success
      assert_select "body", text: /produced no output/
      assert_select "pre", count: 0
    end
  end

  test "a finished job's log is shown" do
    finished = job(state: "done")

    with_stubbed_adapter(apps: [ instance_ ], jobs: [ finished ], log: job_log) do
      get_log

      assert_response :success
      assert_select "pre code", text: /Cloning into 'peertube'/
    end
  end

  test "the job must belong to the app in the URL" do
    other = job(id: "install-1", instance_id: "other-app")

    with_stubbed_adapter(apps: [ instance_ ], jobs: [ other ], log: job_log) do
      get_log(app_id: "peertube-zebu", job_id: "install-1")

      assert_response :not_found
    end
  end

  test "an unknown app is a 404" do
    with_stubbed_adapter(apps: [ instance_ ], jobs: [ job ], log: job_log) do
      get_log(app_id: "deleted-app")

      assert_response :not_found
    end
  end

  test "an unknown job is a 404" do
    with_stubbed_adapter(apps: [ instance_ ], jobs: [ job ], log: job_log) do
      get_log(job_id: "no-such-job")

      assert_response :not_found
    end
  end

  test "a backend failure shows a banner rather than raising" do
    with_stubbed_adapter(
      apps: [ instance_ ], jobs: [ job ],
      job_log_raises: DcommsClient::ServerError.new(code: -32603, message: "no such file")
    ) do
      get_log

      assert_response :success
      assert_select "body", text: /no such file/
    end
  end

  test "an unreachable backend shows a banner rather than raising" do
    with_stubbed_adapter(raises: DcommsClient::ConnectionError.new("no route to host")) do
      get_log

      assert_response :success
      assert_select "body", text: /no route to host/
    end
  end

  test "the log page has no missing translations" do
    with_stubbed_adapter(apps: [ instance_ ], jobs: [ job ], log: job_log) do
      get_log

      assert_response :success
      assert_no_match(/translation missing/, response.body)
    end
  end
end
