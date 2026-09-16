require "test_helper"

class OidcConsentTest < ActionDispatch::IntegrationTest
  def setup
    @user = User.create!(username: "consentuser", email: "consent@example.com")
    @client = Doorkeeper::Application.create!(
      name: "Consent Test Client",
      redirect_uri: "https://client.example/cb",
      scopes: "openid username",
      confidential: true
    )
  end

  def test_consent_screen_renders_with_client_and_scopes
    # Log in through the demo session controller (the built-in test login), which sets
    # session[:user_id] exactly as the WebAuthn flow would -- the session key
    # Doorkeeper's resource_owner_authenticator reads.
    post "/demo/session", params: { username: @user.username }
    follow_redirect!

    get "/oauth/authorize", params: authorize_params

    assert_response :success
    assert_includes response.body, "Consent Test Client"
    assert_includes response.body, "Authorization required"
    assert_includes response.body, "Authorize"
    assert_includes response.body, "Deny"
  end

  def test_consent_screen_redirects_to_login_when_unauthenticated
    get "/oauth/authorize", params: authorize_params

    assert_redirected_to "/login"
  end

  private

  def authorize_params
    {
      client_id: @client.uid,
      redirect_uri: @client.redirect_uri,
      response_type: "code",
      scope: "openid username",
      state: "abc123",
      code_challenge: "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
      code_challenge_method: "S256"
    }
  end
end
