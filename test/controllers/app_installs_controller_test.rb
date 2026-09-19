require_relative "../test_helper"

#
# Integration tests for the install flow: the form modal, and the POST that starts the job.
#
# The adapter is stubbed so these run without a live dcommsctl. What matters here is the
# dialog contract -- both actions answer into `modal-frame` as turbo streams, a failure keeps
# the dialog open with a reason rather than 500ing, and the instance id the daemon assigns is
# what Close links to.
#
class AppInstallsControllerTest < ActionDispatch::IntegrationTest
  # What the browser sends for a turbo_stream request; the templates only match it.
  TURBO_STREAM = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  def setup
    @user = User.create!(username: "install-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
  end

  def with_stubbed_adapter(entry: nil, entry_raises: nil, install: nil, install_raises: nil)
    fake = Object.new
    fake.define_singleton_method(:catalog_entry) do |id:|
      raise entry_raises if entry_raises

      entry
    end
    fake.define_singleton_method(:install) do |name:, domain:|
      raise install_raises if install_raises

      install
    end

    AppInstallsController.alias_method(:adapter_without_stub, :adapter)
    AppInstallsController.define_method(:adapter) { fake }
    yield
  ensure
    AppInstallsController.alias_method(:adapter, :adapter_without_stub)
    AppInstallsController.send(:remove_method, :adapter_without_stub)
  end

  def entry(id: "peertube", name: "Peertube")
    Dcomms::CatalogEntry.new(id: id, name: name)
  end

  def install_result(job_id: "install-1", instance_id: "peertube-zebu")
    Dcomms::InstallResult.new(job_id: job_id, instance_id: instance_id,
                              client_id: "cid", client_secret: "secret")
  end

  ##
  ## access
  ##

  test "new requires an admin" do
    get install_catalog_path("peertube"), headers: TURBO_STREAM

    assert_not_equal 200, response.status
  end

  test "create requires an admin" do
    post install_app_path, params: { app_id: "peertube", domain: "pt.test" }, headers: TURBO_STREAM

    assert_not_equal 200, response.status
  end

  ##
  ## the form modal
  ##

  test "new answers into the modal frame as a turbo stream" do
    with_stubbed_adapter(entry: entry) do
      login_as(@user)
      get install_catalog_path("peertube"), headers: TURBO_STREAM

      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_match(/turbo-stream action="update" target="modal-frame"/, response.body)
    end
  end

  test "new offers a domain field and names the entry being installed" do
    with_stubbed_adapter(entry: entry(name: "Peertube")) do
      login_as(@user)
      get install_catalog_path("peertube"), headers: TURBO_STREAM

      assert_select "input[name='domain']"
      assert_select "input[name='app_id'][value='peertube']"
      assert_select "body", text: /Peertube/
    end
  end

  test "new does not offer the install button as disabled" do
    # Regression guard: the button was a disabled placeholder before install was wired up.
    with_stubbed_adapter(entry: entry) do
      login_as(@user)
      get install_catalog_path("peertube"), headers: TURBO_STREAM

      assert_select "button[disabled]", count: 0
    end
  end

  test "new reports an unreachable backend inside the dialog" do
    with_stubbed_adapter(entry_raises: DcommsClient::ConnectionError.new("no route to host")) do
      login_as(@user)
      get install_catalog_path("peertube"), headers: TURBO_STREAM

      assert_response :success
      assert_select "body", text: /no route to host/
    end
  end

  ##
  ## starting the install
  ##

  test "create passes the app id and domain to the daemon" do
    sent = nil
    # The result is captured as a local because a `define_singleton_method` block does not
    # close over the test instance, so it cannot call `install_result` itself.
    result = install_result
    fake = Object.new
    fake.define_singleton_method(:install) do |name:, domain:|
      sent = { name: name, domain: domain }
      result
    end

    AppInstallsController.alias_method(:adapter_without_stub, :adapter)
    AppInstallsController.define_method(:adapter) { fake }
    begin
      login_as(@user)
      post install_app_path, params: { app_id: "peertube", domain: "  pt.test  " }, headers: TURBO_STREAM
    ensure
      AppInstallsController.alias_method(:adapter, :adapter_without_stub)
      AppInstallsController.send(:remove_method, :adapter_without_stub)
    end

    # The domain is stripped, so a stray space cannot become part of a hostname.
    assert_equal({ name: "peertube", domain: "pt.test" }, sent)
  end

  test "create shows the progress dialog with the instance the daemon assigned" do
    with_stubbed_adapter(install: install_result(instance_id: "peertube-zebu")) do
      login_as(@user)
      post install_app_path, params: { app_id: "peertube", domain: "pt.test" }, headers: TURBO_STREAM

      assert_response :success
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_match(/target="modal-frame"/, response.body)
      assert_select "body", text: /peertube-zebu/
    end
  end

  test "the progress dialog's Close links to the app show page" do
    # The dialog is dismissed into the instance's own page, whether or not the job has
    # finished -- the job continues in the background either way.
    with_stubbed_adapter(install: install_result(instance_id: "peertube-zebu")) do
      login_as(@user)
      post install_app_path, params: { app_id: "peertube", domain: "pt.test" }, headers: TURBO_STREAM

      assert_select "a[href=?]", app_path("peertube-zebu")
    end
  end

  test "create follows the job so the dialog can stream its output" do
    # The dialog is useless without this: the job is what polls dcommsctl and broadcasts into
    # the targets the dialog renders.
    with_stubbed_adapter(install: install_result(job_id: "install-9", instance_id: "peertube-zebu")) do
      enqueued = []
      AppInstallJob.define_singleton_method(:perform_later) { |*args| enqueued << args }
      begin
        login_as(@user)
        post install_app_path, params: { app_id: "peertube", domain: "pt.test" }, headers: TURBO_STREAM
      ensure
        AppInstallJob.singleton_class.send(:remove_method, :perform_later)
      end

      assert_equal [ [ "install-9", "peertube-zebu" ] ], enqueued
    end
  end

  test "the progress dialog subscribes to the job's stream and renders its targets" do
    with_stubbed_adapter(install: install_result(job_id: "install-9")) do
      AppInstallJob.define_singleton_method(:perform_later) { |*, **| nil }
      begin
        login_as(@user)
        post install_app_path, params: { app_id: "peertube", domain: "pt.test" }, headers: TURBO_STREAM
      ensure
        AppInstallJob.singleton_class.send(:remove_method, :perform_later)
      end

      assert_response :success
      # The subscription, and the two elements the job broadcasts into.
      assert_match(/turbo-cable-stream-source/, response.body)
      assert_select "#install-log"
      assert_select "#install-status"
    end
  end

  test "the progress dialog's state label is a label, not the whole state hash" do
    # Regression guard: the view asked for `jobs.state`, which is the hash of all four state
    # names, and rendered it into the page.
    with_stubbed_adapter(install: install_result) do
      AppInstallJob.define_singleton_method(:perform_later) { |*, **| nil }
      begin
        login_as(@user)
        post install_app_path, params: { app_id: "peertube", domain: "pt.test" }, headers: TURBO_STREAM
      ensure
        AppInstallJob.singleton_class.send(:remove_method, :perform_later)
      end

      assert_no_match(/pending: /, response.body)
      assert_select "body", text: /State/
    end
  end

  test "a blank domain is refused before the backend is called" do
    called = false
    result = install_result
    fake = Object.new
    fake.define_singleton_method(:install) do |name:, domain:|
      called = true
      result
    end
    fake.define_singleton_method(:catalog_entry) { |id:| Dcomms::CatalogEntry.new(id: id, name: "Peertube") }

    AppInstallsController.alias_method(:adapter_without_stub, :adapter)
    AppInstallsController.define_method(:adapter) { fake }
    begin
      login_as(@user)
      post install_app_path, params: { app_id: "peertube", domain: "   " }, headers: TURBO_STREAM
    ensure
      AppInstallsController.alias_method(:adapter, :adapter_without_stub)
      AppInstallsController.send(:remove_method, :adapter_without_stub)
    end

    assert_not called, "the daemon must not be called without a domain"
    assert_select "body", text: /A domain is required/
  end

  test "a rejected domain re-renders the form instead of losing it" do
    # Regression guard: the first version replaced the whole dialog with the error, so the
    # field and the Install button disappeared and the user had to close and start over.
    with_stubbed_adapter(entry: entry, install_raises: nil) do
      login_as(@user)
      post install_app_path, params: { app_id: "peertube", domain: "" }, headers: TURBO_STREAM

      assert_response :success
      assert_select "body", text: /A domain is required/
      assert_select "input[name='domain']", nil, "the field must survive the error"
      assert_select "input[name='app_id'][value='peertube']"
      assert_select "button[type='submit']", text: /Install/
    end
  end

  test "a rejected domain updates the dialog in place rather than replacing it" do
    # Regression guard for modal STACKING: replacing `modal-frame` created a second Bootstrap
    # modal while the first was still open, and the old element was never disposed. The
    # re-render must target the inner frame instead.
    with_stubbed_adapter(entry: entry) do
      login_as(@user)
      post install_app_path, params: { app_id: "peertube", domain: "" }, headers: TURBO_STREAM

      assert_match(/target="install-dialog"/, response.body)
      assert_no_match(/target="modal-frame"/, response.body,
                      "a re-render must not replace the modal element itself")
      assert_no_match(/class="modal /, response.body,
                      "a re-render must not render another modal")
    end
  end

  test "a rejected domain keeps the value the user typed" do
    # Currently the only rejection is "blank", so there is nothing to echo and the field
    # simply survives empty. `@domain` is still passed to the field so that a future
    # validation (a bad hostname, say) does not silently discard what was typed; this pins
    # the field's presence rather than a value the controller cannot produce yet.
    with_stubbed_adapter(entry: entry) do
      login_as(@user)
      post install_app_path, params: { app_id: "peertube", domain: "   " }, headers: TURBO_STREAM

      assert_select "body", text: /A domain is required/
      assert_select "input[name='domain']"
    end
  end

  test "create renders the failure in the dialog rather than raising" do
    with_stubbed_adapter(install_raises: DcommsClient::ServerError.new(code: -32603, message: "no work")) do
      login_as(@user)
      post install_app_path, params: { app_id: "peertube", domain: "pt.test" }, headers: TURBO_STREAM

      assert_response :success
      assert_select "body", text: /Could not start the install/
      assert_select "body", text: /no work/
    end
  end

  test "the empty-install guard surfaces rather than reporting success" do
    # `inst/install` returns a zero-value struct with no error for unimplemented apps, which
    # DcommsClient turns into EmptyResult. It must not render as a started install.
    with_stubbed_adapter(install_raises: DcommsClient::EmptyResult.new("dcommsctl reported no work")) do
      login_as(@user)
      post install_app_path, params: { app_id: "mastodon", domain: "m.test" }, headers: TURBO_STREAM

      assert_response :success
      assert_select "body", text: /Could not start the install/
    end
  end

  test "the dialogs have no missing translations" do
    with_stubbed_adapter(entry: entry) do
      login_as(@user)
      get install_catalog_path("peertube"), headers: TURBO_STREAM

      assert_no_match(/translation missing/, response.body)
    end

    with_stubbed_adapter(install: install_result) do
      login_as(@user)
      post install_app_path, params: { app_id: "peertube", domain: "pt.test" }, headers: TURBO_STREAM

      assert_no_match(/translation missing/, response.body)
    end
  end
end
