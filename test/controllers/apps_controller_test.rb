require_relative "../test_helper"

#
# Integration tests for the installed-apps index.
#
# The adapter is stubbed so these run without a live dcommsctl. What matters here is the
# page's behaviour: it lists installed apps, it tolerates a broken backend, and it is
# honest that `inst/list` does not send version/domain yet.
#
class AppsControllerTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(username: "apps-test-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
  end

  # Replace the controller's adapter with a stub returning the given apps (or raising, to
  # exercise the unreachable path).
  #
  # The real `adapter` is aliased aside and restored afterwards. It must not be removed:
  # `remove_method` would drop the controller's own method for the rest of the process, so
  # any later test that exercises the real path fails with a confusing
  # "undefined local variable or method 'adapter'".
  def with_stubbed_adapter(apps: [], raises: nil)
    fake = Object.new
    fake.define_singleton_method(:apps_installed_list) do
      raise raises if raises
      apps
    end

    AppsController.alias_method(:adapter_without_stub, :adapter)
    AppsController.define_method(:adapter) { fake }
    yield
  ensure
    AppsController.alias_method(:adapter, :adapter_without_stub)
    AppsController.send(:remove_method, :adapter_without_stub)
  end

  # An AppInstance as `inst/list` currently returns one: id only.
  #
  # Named `instance_` rather than `app`, which would shadow the `app_path` route helper
  # (`/apps/:id`) that `resources :apps` generates.
  def instance_(id: "peertube-zebu", catalog_entry_id: nil, domain: nil, version: nil, status: nil)
    Dcomms::AppInstance.new(
      id: id, catalog_entry_id: catalog_entry_id, domain: domain, version: version, status: status
    )
  end

  # Replace the controller's adapter with one wired to a REAL DcommsClient whose JSON-RPC
  # exchange is stubbed. Unlike `instance_`, this goes through the actual wire shape, so it
  # catches the adapter or client dropping a field the daemon sends (which is exactly how
  # status once arrived as nil while the backend was reporting "stopped").
  def with_daemon_payload(result)
    client = DcommsClient.new
    client.define_singleton_method(:exchange) do |_payload|
      { "jsonrpc" => "2.0", "id" => "x", "result" => result }
    end

    fake = Object.new
    fake.define_singleton_method(:apps_installed_list) { client.apps_installed_list }

    AppsController.alias_method(:adapter_without_stub, :adapter)
    AppsController.define_method(:adapter) { fake }
    yield
  ensure
    AppsController.alias_method(:adapter, :adapter_without_stub)
    AppsController.send(:remove_method, :adapter_without_stub)
  end

  ##
  ## access
  ##

  test "index requires an admin" do
    get apps_path

    assert_response :redirect
  end

  ##
  ## listing
  ##

  test "the real adapter is constructed, not stubbed away" do
    # Every other test here stubs `adapter`, which hides construction bugs: a default
    # DcommsAdapter with nil collaborators raises "undefined method ... for nil" on the first
    # request. This exercises the real path with no stub.
    #
    # The outcome deliberately does NOT depend on whether dcommsctl happens to be running:
    # it must render a page either way, never a 500. Asserting the error banner (as this once
    # did) made the test pass on a machine with no daemon and fail on one with a daemon.
    login_as(@user)
    get apps_path

    assert_response :success
  end

  test "lists every installed app" do
    with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu"), instance_(id: "mastodon-lion") ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select "body", text: /peertube-zebu/
      assert_select "body", text: /mastodon-lion/
    end
  end

  test "renders each app as a card, not a table" do
    with_stubbed_adapter(apps: [ instance_ ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select ".card", count: 1
      assert_select "table", count: 0
    end
  end

  test "each card identifies the app it shows" do
    with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu") ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select ".card", text: /peertube-zebu/
    end
  end

  ##
  ## missing data
  ##

  test "a missing version is marked as a placeholder, not left blank" do
    # `inst/list` returns no version today. A blank cell is ambiguous; the placeholder
    # makes the gap explicit and is flagged so it is never mistaken for real data.
    with_stubbed_adapter(apps: [ instance_(version: nil) ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select "em[data-placeholder='true']", text: "Unknown"
    end
  end

  test "a missing domain is marked as a placeholder" do
    with_stubbed_adapter(apps: [ instance_(domain: nil) ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select "body", text: /Domain/
      assert_select "em[data-placeholder='true']", minimum: 1
    end
  end

  test "a version from the backend is shown as-is, not as a placeholder" do
    with_stubbed_adapter(apps: [ instance_(version: "6.3.0") ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select "body", text: /6\.3\.0/
      assert_select "em[data-placeholder='true']", text: "Unknown", count: 1
    end
  end

  test "a domain from the backend is shown as-is" do
    with_stubbed_adapter(apps: [ instance_(domain: "video.example.com") ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select "body", text: /video\.example\.com/
    end
  end

  test "the catalog entry an app came from is labelled when known" do
    with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu", catalog_entry_id: "peertube") ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select "code", text: "peertube"
    end
  end

  test "no catalog entry label is rendered when the backend sends none" do
    # `inst/list` derives the catalog entry from the instance directory name, so it can be
    # blank. An empty `code` would read as a missing value rather than an absent field.
    with_stubbed_adapter(apps: [ instance_(catalog_entry_id: nil) ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select "code", count: 0
    end
  end

  ##
  ## status badge
  ##

  test "a running app shows a Running badge" do
    with_stubbed_adapter(apps: [ instance_(status: "running") ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select ".badge.text-bg-success", text: "Running"
    end
  end

  test "a stopped app shows a Stopped badge" do
    with_stubbed_adapter(apps: [ instance_(status: "stopped") ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select ".badge.text-bg-secondary", text: "Stopped"
    end
  end

  test "a missing status shows an Unknown badge, not Stopped" do
    # The daemon sends an empty status when it cannot reach docker compose. Reporting that
    # as "stopped" would be a different (and unchecked) claim, so it gets its own label.
    with_stubbed_adapter(apps: [ instance_(status: nil) ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select ".badge.text-bg-dark", text: "Unknown"
      assert_select ".badge", text: "Stopped", count: 0
    end
  end

  test "a blank status from the backend also shows Unknown" do
    # `inst/list` sends "" rather than omitting the key, and AppInstance normalizes that
    # to nil. Both spellings must reach the same badge.
    with_stubbed_adapter(apps: [ instance_(status: "") ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select ".badge.text-bg-dark", text: "Unknown"
    end
  end

  test "an unrecognized status renders no badge at all" do
    # A state we do not know is better left unlabelled than shown in a colour that means
    # something else.
    with_stubbed_adapter(apps: [ instance_(status: "exploded") ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select ".badge", count: 0
    end
  end

  test "the status badge is on the card for the app it describes" do
    with_stubbed_adapter(apps: [
      instance_(id: "peertube-zebu", status: "running"),
      instance_(id: "mastodon-lion", status: "stopped")
    ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select ".card", text: /peertube-zebu.*Running/m
      assert_select ".card", text: /mastodon-lion.*Stopped/m
    end
  end

  test "a real inst/list payload reaches the badge intact" do
    # End-to-end over the daemon's actual wire shape (rpc_inst_list.go's InstanceInfo).
    # Regression guard: the client once collapsed each row to its id, so a daemon reporting
    # "stopped" arrived as nil and rendered as "Unknown".
    payload = {
      "instances" => [
        { "id" => "peertube-zebu", "app" => "peertube", "domain" => "pt.test",
          "version" => "7.0.0", "status" => "stopped" }
      ]
    }

    with_daemon_payload(payload) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select ".badge.text-bg-secondary", text: "Stopped"
      assert_select ".badge", text: "Unknown", count: 0
      assert_select "body", text: /7\.0\.0/
      assert_select "body", text: /pt\.test/
    end
  end

  ##
  ## resilience
  ##

  test "unreachable backend shows a banner rather than raising" do
    with_stubbed_adapter(raises: DcommsClient::ConnectionError.new("no route to host")) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select "body", text: /no route to host/
    end
  end

  test "an empty list explains itself" do
    with_stubbed_adapter(apps: []) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select "body", text: /No apps are installed yet/
    end
  end

  test "a list that is empty because of an error does not claim it is empty" do
    with_stubbed_adapter(raises: DcommsClient::ProtocolError.new("garbage")) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_no_match(/No apps are installed yet/, response.body)
    end
  end

  test "an error renders the banner and nothing else" do
    with_stubbed_adapter(raises: DcommsClient::ConnectionError.new("no route to host")) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select ".card", count: 0, message: "no cards should render when the backend failed"
    end
  end

  test "a successful load renders the cards and no error banner" do
    with_stubbed_adapter(apps: [ instance_ ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select ".card", count: 1
      assert_select "div.alert-danger", count: 0
    end
  end

  ##
  ## translation hygiene
  ##

  test "index has no missing translations" do
    with_stubbed_adapter(apps: [ instance_ ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_no_match(/translation missing/, response.body)
    end
  end

  test "index leaks no Haml markup into the output" do
    # A stray `=` in an attribute position turns into literal text, which renders on the
    # page and passes every content assertion that does not look for it.
    with_stubbed_adapter(apps: [ instance_ ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_no_match(/= t\(/, response.body)
      assert_no_match(/translation_missing/, response.body)
    end
  end

  test "the index links to the catalog to install an app" do
    with_stubbed_adapter(apps: [ instance_ ]) do
      login_as(@user)
      get apps_path

      assert_response :success
      assert_select "a[href=?]", catalog_index_path
    end
  end
end
