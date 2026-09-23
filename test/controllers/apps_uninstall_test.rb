require_relative "../test_helper"

#
# Integration tests for removing an app instance.
#
# The adapter is stubbed so these run without a live dcommsctl. What matters here is the contract
# of the confirmation step: neither the show page's link nor anything else can remove an app
# without the instance name being typed, a rejected attempt keeps the user on a page they can
# correct, and a removal that the daemon accepts is reported as started rather than as finished
# (the daemon's job is not followed -- see AppsController#destroy).
#
class AppsUninstallTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(username: "uninstall-#{SecureRandom.hex(4)}", is_admin: true, is_active: true)
  end

  # Replace the controller's adapter with a stub. `apps` is what `inst/list` reports; `raises`
  # makes that lookup itself fail; `uninstall` records what the removal was called with.
  def with_stubbed_adapter(apps: [], raises: nil, uninstall_raises: nil)
    called = []
    fake = Object.new
    fake.define_singleton_method(:apps_installed_list) do
      raise raises if raises

      apps
    end
    fake.define_singleton_method(:uninstall) do |id:|
      # Recorded BEFORE the raise, so `called` means "the daemon was asked" in both outcomes:
      # that is what makes `assert_empty called` in the refusal tests a claim about the daemon
      # never being reached, rather than about the stub's failure mode.
      called << id
      raise uninstall_raises if uninstall_raises

      "uninstall-1"
    end

    AppsController.alias_method(:adapter_without_stub, :adapter)
    AppsController.define_method(:adapter) { fake }
    [ called, yield ]
  ensure
    AppsController.alias_method(:adapter, :adapter_without_stub)
    AppsController.send(:remove_method, :adapter_without_stub)
  end

  def instance_(id: "peertube-zebu", catalog_entry_id: "peertube", domain: "pt.test",
                version: "7.0.0", status: "running")
    Dcomms::AppInstance.new(
      id: id, catalog_entry_id: catalog_entry_id, domain: domain, version: version, status: status
    )
  end

  def confirm(id = "peertube-zebu")
    delete uninstall_app_path(id), params: { confirm_id: id }
  end

  def get_confirmation(id = "peertube-zebu")
    login_as(@user)
    get uninstall_app_path(id)
  end

  ##
  ## access
  ##

  test "the confirmation page requires an admin" do
    get uninstall_app_path("peertube-zebu")

    assert_response :redirect
  end

  test "performing the removal requires an admin" do
    delete uninstall_app_path("peertube-zebu"), params: { confirm_id: "peertube-zebu" }

    assert_response :redirect
  end

  ##
  ## the confirmation page
  ##

  test "the confirmation page names the app it is about to remove" do
    with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu") ]) do
      get_confirmation

      assert_response :success
      assert_select "h3", text: /Remove peertube-zebu/
    end
  end

  test "the confirmation page asks for the instance name to be typed" do
    # The field is the confirmation, so its label has to say what to type. A form without it
    # would still submit, and the controller would reject everything with no way to succeed.
    with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu") ]) do
      get_confirmation

      assert_response :success
      assert_select "label", text: /Type peertube-zebu to confirm/
      assert_select "input[name='confirm_id']"
    end
  end

  test "the confirmation page submits a DELETE to the removal url" do
    # A GET or a plain POST here would make the removal reachable by anything that can follow a
    # url, which is what the typed name is supposed to prevent.
    with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu") ]) do
      get_confirmation

      assert_response :success
      assert_select "form[action=?][method=post]", uninstall_app_path("peertube-zebu") do
        assert_select "input[name='_method'][value='delete']"
      end
    end
  end

  test "the confirmation page says what removal does and does not do" do
    # `inst/uninstall` runs `docker compose down` and keeps the instance's data, so the page must
    # not promise a clean slate or claim it cannot be undone.
    with_stubbed_adapter(apps: [ instance_ ]) do
      get_confirmation

      assert_select ".alert-warning", text: /data is kept/
    end
  end

  test "the confirmation page offers a way out that does not remove anything" do
    with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu") ]) do
      get_confirmation

      assert_response :success
      assert_select "a[href=?]", app_path("peertube-zebu"), text: /Cancel/i
    end
  end

  test "an app the backend does not report is explained, with no field to type into" do
    # Someone else removed it, or the daemon lost it. Offering the field would give the user a
    # form whose only possible outcome is an error.
    with_stubbed_adapter(apps: [ instance_(id: "other-app") ]) do
      get_confirmation

      assert_response :success
      assert_select "body", text: /no longer installed/
      assert_select "input[name='confirm_id']", count: 0
    end
  end

  test "an unreachable backend is explained on the confirmation page" do
    with_stubbed_adapter(raises: DcommsClient::ConnectionError.new("no route to host")) do
      get_confirmation

      assert_response :success
      assert_select "body", text: /no route to host/
      assert_select "input[name='confirm_id']", count: 0
    end
  end

  ##
  ## confirming
  ##

  test "the exact instance name removes the app and reports it as started" do
    called, = with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu") ]) do
      login_as(@user)
      confirm
    end

    assert_equal [ "peertube-zebu" ], called
    assert_redirected_to apps_path
    assert_match(/Removing peertube-zebu/, flash[:notice])
  end

  test "the app is looked up, so the id sent to the daemon is the backend's" do
    # The instance id is the daemon's, not whatever is in the url: the lookup is what guarantees
    # the removal names a real instance rather than a hand-typed string.
    called, = with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu") ]) do
      login_as(@user)
      delete uninstall_app_path("peertube-zebu"), params: { confirm_id: "peertube-zebu" }
    end

    assert_equal [ "peertube-zebu" ], called
  end

  test "surrounding whitespace in the typed name is ignored" do
    # A pasted name often carries it, and rejecting that would be a puzzle rather than a
    # safeguard.
    called, = with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu") ]) do
      login_as(@user)
      delete uninstall_app_path("peertube-zebu"), params: { confirm_id: "  peertube-zebu\n" }
    end

    assert_equal [ "peertube-zebu" ], called
  end

  ##
  ## refusing
  ##

  test "a missing name does not reach the daemon" do
    called, = with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu") ]) do
      login_as(@user)
      delete uninstall_app_path("peertube-zebu"), params: {}
    end

    assert_empty called, "the daemon must not be asked to remove anything without the name"
    assert_response :unprocessable_entity
    assert_select "body", text: /does not match peertube-zebu/
  end

  test "a wrong name does not reach the daemon" do
    called, = with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu") ]) do
      login_as(@user)
      delete uninstall_app_path("peertube-zebu"), params: { confirm_id: "mastodon-lion" }
    end

    assert_empty called
    assert_response :unprocessable_entity
  end

  test "a partial name is not enough" do
    # The check is equality, not a substring or a prefix: "peertube" is what someone types when
    # they have not read which instance this is.
    called, = with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu") ]) do
      login_as(@user)
      delete uninstall_app_path("peertube-zebu"), params: { confirm_id: "peertube" }
    end

    assert_empty called
    assert_response :unprocessable_entity
  end

  test "the name is matched case-sensitively" do
    # Ids are lowercase, so a differently-cased name is a different string. Accepting it would
    # quietly widen what counts as confirmation.
    called, = with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu") ]) do
      login_as(@user)
      delete uninstall_app_path("peertube-zebu"), params: { confirm_id: "Peertube-Zebu" }
    end

    assert_empty called
    assert_response :unprocessable_entity
  end

  test "a rejected attempt keeps what was typed so it can be corrected" do
    with_stubbed_adapter(apps: [ instance_(id: "peertube-zebu") ]) do
      login_as(@user)
      delete uninstall_app_path("peertube-zebu"), params: { confirm_id: "peertub-zebu" }

      assert_response :unprocessable_entity
      assert_select "input[name='confirm_id'][value='peertub-zebu']"
      assert_select "form[action=?]", uninstall_app_path("peertube-zebu")
    end
  end

  test "removing an app the backend does not report does not reach the daemon" do
    called, = with_stubbed_adapter(apps: [ instance_(id: "other-app") ]) do
      login_as(@user)
      confirm
    end

    assert_empty called
    assert_response :unprocessable_entity
    assert_select "body", text: /no longer installed/
  end

  test "a daemon failure is reported on the page rather than as a success" do
    called, = with_stubbed_adapter(
      apps: [ instance_(id: "peertube-zebu") ],
      uninstall_raises: DcommsClient::ServerError.new(code: -32603, message: "boom")
    ) do
      login_as(@user)
      confirm
    end

    assert_equal [ "peertube-zebu" ], called
    assert_response :unprocessable_entity
    assert_select "body", text: /boom/
    assert_equal 0, flash[:notice].to_s.length, "a failure must not flash a start notice"
  end

  test "a busy instance is reported and can be retried from the same page" do
    # `inst/uninstall` takes the instance's job lock, so a concurrent install or start is refused
    # with "The job is in progress". The field stays, because once the lock frees the user can
    # simply submit again.
    with_stubbed_adapter(
      apps: [ instance_(id: "peertube-zebu") ],
      uninstall_raises: DcommsClient::JobInProgress.new(code: -32603, message: "The job is in progress")
    ) do
      login_as(@user)
      confirm

      assert_response :unprocessable_entity
      assert_select "body", text: /The job is in progress/
      assert_select "input[name='confirm_id']"
    end
  end

  ##
  ## translation hygiene
  ##

  test "the confirmation page has no missing translations" do
    with_stubbed_adapter(apps: [ instance_ ]) do
      get_confirmation

      assert_no_match(/translation missing/, response.body)
    end
  end

  test "the confirmation page leaks no Haml markup into the output" do
    with_stubbed_adapter(apps: [ instance_ ]) do
      get_confirmation

      assert_no_match(/= t\(/, response.body)
      assert_no_match(/translation_missing/, response.body)
    end
  end
end
