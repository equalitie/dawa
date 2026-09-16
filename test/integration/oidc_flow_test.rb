require "test_helper"

#
# End-to-end tests for Dawa as an OpenID Connect identity provider (Doorkeeper +
# doorkeeper-openid_connect).
#
class OidcFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      username: "oidcuser",
      email: "oidcuser@example.com",
      display_name: "Oidc User",
      is_admin: false
    )
    @client = Doorkeeper::Application.create!(
      name: "OIDC Client",
      redirect_uri: "https://client.example/cb",
      scopes: "openid username email",
      confidential: true
    )
    @code_challenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
    @code_verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
  end

  def test_discovery_document
    get "/.well-known/openid-configuration"
    assert_response :success
    body = JSON.parse(response.body)
    # The issuer is the bare provider URL (matches what clients are configured with);
    # the endpoints are under /oauth.
    assert_equal host, body["issuer"]
    assert_equal "#{host}/oauth/authorize", body["authorization_endpoint"]
    assert_equal "#{host}/oauth/token", body["token_endpoint"]
    assert_equal "#{host}/oauth/userinfo", body["userinfo_endpoint"]
    assert_equal "#{host}/oauth/discovery/keys", body["jwks_uri"]
    assert_includes body["scopes_supported"], "openid"
    assert_includes body["scopes_supported"], "username"
  end

  def test_jwks_public_key
    get "/oauth/discovery/keys"
    assert_response :success
    keys = JSON.parse(response.body)["keys"]
    assert_equal 1, keys.length
    assert_equal "EC", keys.first["kty"]
    assert keys.first["x"].present?
    assert keys.first["y"].present?
  end

  def test_authorization_code_flow_issues_id_token_and_access_token
    # Log in via the demo session (WebAuthn-equivalent session[:user_id]).
    post "/demo/session", params: { username: @user.username }
    follow_redirect!

    # Consent is skipped (skip_authorization), so authorizing immediately redirects to
    # the client with an authorization code (no consent screen is shown).
    get "/oauth/authorize", params: authorize_params
    assert_response :redirect
    location = URI.parse(response.location)
    assert_equal "https", location.scheme
    assert_equal "client.example", location.host

    query = Rack::Utils.parse_nested_query(location.query)
    code = query["code"]
    assert code.present?, "expected an authorization code, got: #{location.inspect}"
    assert_equal "xyz-state", query["state"]

    # Exchange the code for tokens (PKCE S256).
    post "/oauth/token", as: :json, params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: @client.redirect_uri,
      client_id: @client.uid,
      client_secret: @client.plaintext_secret,
      code_verifier: @code_verifier
    }
    assert_response :success, "token exchange failed: #{response.body}"
    tokens = JSON.parse(response.body)
    assert tokens["access_token"].present?
    assert tokens["id_token"].present?, "expected an id_token"
    assert_equal "openid username email", tokens["scope"]

    # Step 4: decode and verify the id_token against the JWKS public key.
    id_token = verify_id_token(tokens["id_token"])
    assert_equal host, id_token["iss"]
    assert_equal @user.uuid, id_token["sub"]
    assert_equal [ @client.uid ], id_token["aud"]
    assert_equal @user.username, id_token["preferred_username"]
    assert id_token["exp"].to_i > Time.now.to_i

    # Step 5: fetch userinfo with the access token.
    get "/oauth/userinfo", headers: { "Authorization" => "Bearer #{tokens["access_token"]}" }
    assert_response :success
    info = JSON.parse(response.body)
    assert_equal @user.uuid, info["sub"]
    assert_equal @user.username, info["preferred_username"]
    assert_equal @user.email, info["email"]
  end

  def test_unauthenticated_authorize_redirects_to_login
    get "/oauth/authorize", params: authorize_params
    assert_redirected_to "/login"
  end

  #
  # When the user is not yet logged in, /oauth/authorize must redirect to Dawa's
  # login page but remember the original authorize request in session[:redirect] so
  # that (after logging in) the user is returned to /oauth/authorize and the
  # authorization_code OIDC flow completes instead of stranding them on Dawa's home
  # page.
  #
  def test_authorization_code_flow_completes_after_login
    get "/oauth/authorize", params: authorize_params
    assert_redirected_to "/login"
    assert session[:redirect], "expected session[:redirect] to be recorded"
    assert_includes session[:redirect], "/oauth/authorize"

    # Log in (demo login preserves :redirect and returns the user to it).
    post "/demo/session", params: { username: @user.username }
    assert_response :redirect
    redirect_target = URI.parse(response.location)
    assert_equal "/oauth/authorize", redirect_target.path

    follow_redirect!
    assert_response :redirect
    location = URI.parse(response.location)
    assert_equal @client.redirect_uri.split("//").last.split("/").first, location.host

    query = Rack::Utils.parse_nested_query(location.query)
    assert query["code"].present?, "expected an authorization code after login, got #{location.inspect}"
  end

  def test_password_grant_is_rejected
    post "/oauth/token", as: :json, params: {
      grant_type: "password",
      username: @user.username,
      password: "whatever"
    }
    assert_response :bad_request
    assert_equal "unsupported_grant_type", JSON.parse(response.body)["error"]
  end

  private

  def host
    # The discovery document / issuer are pinned to the provider URL (what clients reach
    # Dawa at, e.g. host.docker.internal from a container), not Conf.site_public_url.
    Conf.openid_provider_url
  end

  def authorize_params
    {
      client_id: @client.uid,
      redirect_uri: @client.redirect_uri,
      response_type: "code",
      scope: "openid username email",
      state: "xyz-state",
      code_challenge: @code_challenge,
      code_challenge_method: "S256"
    }
  end

  #
  # Verify the JWT id_token signature against Dawa's signing key (the same key the
  # JWKS endpoint publishes). Uses the jwt gem's ES512 verification, which handles
  # the raw R||S ECDSA signature encoding; returns the decoded payload.
  #
  def verify_id_token(id_token)
    key = OpenSSL::PKey::EC.new(Dawa::OidcKey.to_pem(Conf.openid_private_key))

    payload, = JWT.decode(
      id_token,
      key,
      true,
      algorithm: "ES512"
    )
    payload
  end
end
