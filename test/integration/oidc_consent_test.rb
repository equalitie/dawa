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

  def test_authorize_is_pre_authorized_when_authenticated
    # Log in through the demo session controller (the built-in test login), which sets
    # session[:user_id] exactly as the WebAuthn flow would -- the session key
    # Doorkeeper's resource_owner_authenticator reads.
    post "/demo/session", params: { username: @user.username }
    follow_redirect!

    # Consent is skipped (skip_authorization => true), so the authorize request is
    # pre-authorized: it immediately redirects to the client with a code, never
    # rendering the consent (authorizations/new) screen.
    get "/oauth/authorize", params: authorize_params
    assert_response :redirect
    location = URI.parse(response.location)
    assert_equal "client.example", location.host
    query = Rack::Utils.parse_nested_query(location.query)
    assert query["code"].present?, "expected an authorization code, got: #{location.inspect}"
    assert_equal "abc123", query["state"]
  end

  def test_authorize_redirects_to_login_when_unauthenticated
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
