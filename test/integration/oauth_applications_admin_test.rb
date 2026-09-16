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
    get "/settings/oauth-applications"
    assert_response :success
    assert_includes response.body, "Listed Client"
  end

  def test_create_application
    login
    assert_difference "Doorkeeper::Application.count", 1 do
      post "/settings/oauth-applications", params: {
        oauth_application: { name: "New Client", redirect_uri: "https://cb.example/cb", scopes: "openid email", confidential: true }
      }
    end
    assert_redirected_to %r{/settings/oauth-applications/\d+}
    app = Doorkeeper::Application.order(:id).last
    assert_equal "New Client", app.name
    assert_equal %w[openid email], app.scopes.to_a
    assert app.confidential?
  end

  def test_rotate_secret_changes_secret
    app = Doorkeeper::Application.create!(
      name: "Rotate Me", redirect_uri: "https://cb.example/cb", scopes: "openid", confidential: true
    )
    old_stored_secret = app.secret
    login
    patch "/settings/oauth-applications/#{app.id}/rotate"
    assert_redirected_to "/settings/oauth-applications/#{app.id}"
    assert_not_equal old_stored_secret, app.reload.secret
  end

  def test_destroy_application
    app = Doorkeeper::Application.create!(
      name: "Delete Me", redirect_uri: "https://cb.example/cb", scopes: "openid", confidential: true
    )
    login
    assert_difference "Doorkeeper::Application.count", -1 do
      delete "/settings/oauth-applications/#{app.id}"
    end
    assert_redirected_to "/settings/oauth-applications"
  end

  def test_show_displays_client_details
    app = Doorkeeper::Application.create!(
      name: "Detail Client", redirect_uri: "https://cb.example/cb", scopes: "openid username", confidential: true
    )
    login
    get "/settings/oauth-applications/#{app.id}"
    assert_response :success
    assert_includes response.body, app.name
    assert_includes response.body, app.uid
  end

  def test_non_admin_is_forbidden
    user = User.create!(username: "oidc-regular", email: "oidc-regular@example.com", is_admin: false, is_active: true)
    login(user)
    get "/settings/oauth-applications"
    assert_response :forbidden
  end
end
