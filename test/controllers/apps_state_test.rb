require_relative "../test_helper"

#
# Integration tests for the start/stop buttons on an app.
#
# The adapter is stubbed so these run without a live dcommsctl. What matters here is the contract
# the buttons depend on: the command reaches the daemon under the name the button sent, the page is
# answered with a turbo STREAM (a bare 200 is rejected by Turbo for a non-safe form submission --
# see AppsController#update), and a refusal is reported in the page rather than as a 500.
#
class AppsStateTest < ActionDispatch::IntegrationTest
  TURBO_STREAM = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  def setup
    @user = User.create!(username: "state-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
  end

  # Replace the controller's adapter. Returns the recorded command names, so a test can assert both
  # WHICH command went to the daemon and that nothing was sent when it should not have been.
  def with_stubbed_adapter(apps: [], raises: nil, command_raises: nil)
    commands = []
    fake = Object.new
    fake.define_singleton_method(:apps_installed_list) do
      raise raises if raises

      apps
    end
    # `restart` is composed from `stop`, so the stub records it as its own name: that is what the
    # controller calls, and recording the composed call is how a test can tell a restart apart from
    # a plain stop.
    %i[start stop restart].each do |name|
      fake.define_singleton_method(name) do |id:|
        # Recorded before any raise, so an empty list means "the daemon was never asked" rather
        # than "the stub happened to fail".
        commands << [ name, id ]
        raise command_raises if command_raises

        "#{name}-job-1"
      end
    end

    AppsController.alias_method(:adapter_without_stub, :adapter)
    AppsController.define_method(:adapter) { fake }
    [ commands, yield ]
  ensure
    AppsController.alias_method(:adapter, :adapter_without_stub)
    AppsController.send(:remove_method, :adapter_without_stub)
  end

  def instance_(id: "peertube-zebu", status: "stopped")
    Dcomms::AppInstance.new(id: id, catalog_entry_id: "peertube", domain: "pt.test", status: status)
  end

  # `perform_later` would enqueue a real job that polls a daemon that is not running.
  def with_recorded_job_enqueue
    enqueued = []
    AppStateJob.define_singleton_method(:perform_later) { |*args| enqueued << args }
    yield
    enqueued
  ensure
    AppStateJob.singleton_class.send(:remove_method, :perform_later)
  end

  def send_command(command, id: "peertube-zebu")
    login_as(@user)
    put app_path(id), params: { command: command }, headers: TURBO_STREAM
  end

  ##
  ## access
  ##

  test "sending a command requires an admin" do
    # Enforced by BaseAdminController's `permit!`, which raises ForbiddenRequest; the auth engine
    # answers a stream request with 401 and an HTML one with a redirect to login. Both refuse, so
    # both shapes are pinned rather than assuming one.
    put app_path("peertube-zebu"), params: { command: "start" }, headers: TURBO_STREAM
    assert_response :unauthorized

    put app_path("peertube-zebu"), params: { command: "start" }
    assert_response :redirect
  end

  ##
  ## dispatching
  ##

  test "start sends inst/start and answers with a turbo stream" do
    commands, = with_stubbed_adapter(apps: [ instance_ ]) do
      with_recorded_job_enqueue { send_command("start") }
    end

    assert_equal [ [ :start, "peertube-zebu" ] ], commands
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
  end

  test "stop sends inst/stop" do
    commands, = with_stubbed_adapter(apps: [ instance_(status: "running") ]) do
      with_recorded_job_enqueue { send_command("stop") }
    end

    assert_equal [ [ :stop, "peertube-zebu" ] ], commands
  end

  test "restart sends inst/stop first, since the daemon has no inst/restart" do
    # The stop half is issued by the controller. The start half is issued by AppStateJob once the
    # stop reports terminal, so only the stop is observable at request time.
    commands, = with_stubbed_adapter(apps: [ instance_(status: "running") ]) do
      with_recorded_job_enqueue { send_command("restart") }
    end

    assert_equal [ [ :restart, "peertube-zebu" ] ], commands
  end

  test "restart hands the command name to the follower so the start half runs" do
    with_stubbed_adapter(apps: [ instance_(status: "running") ]) do
      enqueued = with_recorded_job_enqueue { send_command("restart") }

      assert_equal [ [ { job_id: "restart-job-1", app_id: "peertube-zebu", command: "restart" } ] ], enqueued
    end
  end

  test "a restart in flight shows one restarting button, not start or stop" do
    with_stubbed_adapter(apps: [ instance_(status: "running") ]) do
      with_recorded_job_enqueue { send_command("restart") }

      assert_match(/target="app-box"/, response.body)
      assert_select "body", text: /Restarting/
      # Only the restart button spins: the other two are present but disabled.
      assert_select "button[disabled]", count: 3
      assert_select "button:not([disabled])", count: 0
    end
  end

  test "the daemon's job id and the instance are handed to the follower" do
    # Without this the page would never learn the new state: the job is what polls `job/status` and
    # broadcasts the result. The command name travels too, because a restart is sequenced as two
    # jobs and the follower has to know which one it is running.
    with_stubbed_adapter(apps: [ instance_ ]) do
      enqueued = with_recorded_job_enqueue { send_command("start") }

      assert_equal [ [ { job_id: "start-job-1", app_id: "peertube-zebu", command: "start" } ] ], enqueued
    end
  end

  test "the response replaces the app's box with the command in flight" do
    # The pressed button has to disappear immediately, or the user can submit a second command
    # while the first still holds the instance's lock.
    with_stubbed_adapter(apps: [ instance_ ]) do
      with_recorded_job_enqueue { send_command("start") }

      assert_match(/turbo-stream action="replace" target="app-box"/, response.body)
      assert_select "body", text: /Starting/
    end
  end

  test "an unknown command is refused without reaching the daemon" do
    # Not reachable from the buttons, which only send the two known names; this pins that the
    # controller whitelists rather than forwarding whatever arrives.
    commands, = with_stubbed_adapter(apps: [ instance_ ]) do
      login_as(@user)
      put app_path("peertube-zebu"), params: { command: "destroy-everything" }, headers: TURBO_STREAM
    end

    assert_empty commands
    assert_response :bad_request
  end

  test "a missing command is refused without reaching the daemon" do
    commands, = with_stubbed_adapter(apps: [ instance_ ]) do
      login_as(@user)
      put app_path("peertube-zebu"), params: {}, headers: TURBO_STREAM
    end

    assert_empty commands
    assert_response :bad_request
  end

  test "an instance the backend does not report is not commanded" do
    commands, = with_stubbed_adapter(apps: [ instance_(id: "other-app") ]) do
      with_recorded_job_enqueue { send_command("start") }
    end

    assert_empty commands
    assert_response :success
    assert_select "body", text: /no longer installed/
  end

  ##
  ## refusals
  ##

  test "a busy instance is reported in the box rather than as an error page" do
    # `inst/start` takes the instance's job lock, so a concurrent install is refused with "The job
    # is in progress". The box is kept (the page has nothing else to offer) with the reason above
    # buttons that can be tried again.
    error = DcommsClient::JobInProgress.new(code: -32603, message: "The job is in progress")

    with_stubbed_adapter(apps: [ instance_ ], command_raises: error) do
      send_command("start")

      assert_response :success
      assert_match(/target="app-box"/, response.body)
      assert_select "body", text: /The job is in progress/
      # The buttons are still there, so the user can retry once the lock frees.
      assert_select "button[form]", text: /Start/
    end
  end

  test "an unreachable backend is reported rather than raising" do
    with_stubbed_adapter(raises: DcommsClient::ConnectionError.new("no route to host")) do
      send_command("start")

      assert_response :success
      assert_select "body", text: /no route to host/
    end
  end

  test "a rejected command does not enqueue a follower" do
    error = DcommsClient::ServerError.new(code: -32603, message: "boom")

    with_stubbed_adapter(apps: [ instance_ ], command_raises: error) do
      enqueued = with_recorded_job_enqueue { send_command("start") }

      assert_empty enqueued
    end
  end

  ##
  ## translation hygiene
  ##

  test "the in-flight box has no missing translations" do
    with_stubbed_adapter(apps: [ instance_ ]) do
      with_recorded_job_enqueue { send_command("start") }

      assert_no_match(/translation missing/, response.body)
    end
  end
end
