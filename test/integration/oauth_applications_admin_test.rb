require "test_helper"

class OauthApplicationsAdminTest < ActionDispatch::IntegrationTest
  def setup
    @admin = User.create!(username: "oidc-admin", email: "oidc-admin@example.com", is_admin: true, is_active: true)
  end

  def login(user = @admin)
    post "/demo/session", params: { username: user.username }
    follow_redirect!
  end

  def test_index_lists_applications_for_admin
    Doorkeeper::Application.create!(
      name: "Listed Client", redirect_uri: "https://cb.example/cb", scopes: "openid", confidential: true
    )
    login
    get "/oauth/applications"
    assert_response :success
    assert_includes response.body, "Listed Client"
  end

  def test_new_page_renders_the_form
    login
    get "/oauth/applications/new"
    assert_response :success
    assert_select "form"
    assert_select "[name='oauth_application[name]']"
  end

  def test_new_page_scope_checklist
    login
    get "/oauth/applications/new"
    assert_response :success

    # Default scopes are checked and disabled (not selectable).
    assert_select "input[type=checkbox][value=openid][checked=checked][disabled=disabled]"
    # Optional scopes are enabled (no disabled attr) and unchecked by default.
    %w[username email profile].each do |scope|
      assert_select "input[type=checkbox][value=#{scope}]" do |boxes|
        assert_equal 1, boxes.length
        assert_nil boxes.first.attr("disabled").presence
        assert_nil boxes.first.attr("checked")
      end
    end
  end

  def test_edit_page_renders_the_form
    app = Doorkeeper::Application.create!(
      name: "Edit Me", redirect_uri: "https://cb.example/cb", scopes: "openid username", confidential: true
    )
    login
    get "/oauth/applications/#{app.id}/edit"
    assert_response :success
    assert_select "form"
    assert_select "[name='oauth_application[name]'][value='Edit Me']"
    # Optional scopes already on the record are pre-checked.
    assert_select "input[type=checkbox][value=username][checked=checked]"
    assert_select "input[type=checkbox][value=profile]" do |boxes|
      assert_equal 1, boxes.length
      assert_nil boxes.first.attr("checked")
    end
  end

  def test_create_application
    login
    assert_difference "Doorkeeper::Application.count", 1 do
      post "/oauth/applications", params: {
        oauth_application: { name: "New Client", redirect_uri: "https://cb.example/cb", scopes: %w[username email], confidential: true }
      }
    end
    # The controller redirects to the edit page (the show action/route is not used).
    assert_redirected_to %r{/oauth/applications/\d+/edit}
    app = Doorkeeper::Application.order(:id).last
    assert_equal "New Client", app.name
    # Only the selected optional scopes are stored; default scopes (e.g. `openid`) are
    # applied by doorkeeper itself and intentionally not persisted on the record.
    assert_equal %w[username email], app.scopes.to_a
    assert app.confidential?
  end

  def test_rotate_secret_changes_secret
    app = Doorkeeper::Application.create!(
      name: "Rotate Me", redirect_uri: "https://cb.example/cb", scopes: "openid", confidential: true
    )
    old_stored_secret = app.secret
    login
    # Rotation is now folded into the `update` action, triggered by a `rotate` param.
    patch "/oauth/applications/#{app.id}", params: { rotate: true }
    assert_redirected_to "/oauth/applications/#{app.id}/edit"
    assert_not_equal old_stored_secret, app.reload.secret
  end

  def test_destroy_application
    app = Doorkeeper::Application.create!(
      name: "Delete Me", redirect_uri: "https://cb.example/cb", scopes: "openid", confidential: true
    )
    login
    assert_difference "Doorkeeper::Application.count", -1 do
      delete "/oauth/applications/#{app.id}"
    end
    assert_redirected_to "/oauth/applications"
  end

  def test_non_admin_is_forbidden
    user = User.create!(username: "oidc-regular", email: "oidc-regular@example.com", is_admin: false, is_active: true)
    login(user)
    get "/oauth/applications"
    assert_response :forbidden
  end
end
