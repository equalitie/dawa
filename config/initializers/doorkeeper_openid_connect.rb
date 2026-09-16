# frozen_string_literal: true

#
# OIDC `aud` claim handling.
#
# doorkeeper-openid_connect emits the `aud` claim in the ID token as a single string
# (the client_id). Some OIDC client libraries (e.g. Go's oidc-tester-app, which decodes
# `aud` as `[]string`) expect `aud` to be a JSON array. OIDC Core permits `aud` to be a
# single string or an array of strings, so emitting it as a one-element array is the most
# broadly compatible choice.
#
module OpenidConnectAudArray
  def audience
    Array(@access_token.application.try(:uid))
  end
end
Doorkeeper::OpenidConnect::IdToken.prepend(OpenidConnectAudArray)

Doorkeeper::OpenidConnect.configure do
  # The issuer is the absolute URL clients use for discovery and token validation. It MUST
  # be identical across every endpoint, otherwise strict clients reject mis-matched issuers.
  # We therefore derive it from the stable (per environment) public URL rather than the
  # per-request host, so the discovery document, authorize, and token endpoints all agree.
  # The OAuth provider is mounted at /oauth.
  issuer "#{Conf.openid_provider_url}"

  signing_key File.read("config/oidc_signing_key.pem")

  # `signing_key` also accepts an array for key rotation. The first entry is
  # the active key used to sign newly issued ID tokens; any remaining entries
  # are published in the JWKS so clients can still validate tokens signed
  # with a retired key during a rotation window.
  #
  # signing_key [
  #   File.read("config/keys/current.pem"),  # active
  #   File.read("config/keys/previous.pem"), # retired but still in JWKS
  # ]

  subject_types_supported [:public]

  resource_owner_from_access_token do |access_token|
    User.find_by(id: access_token.resource_owner_id)
  end

  auth_time_from_resource_owner do |resource_owner|
    # Used to populate the `auth_time` claim on the ID Token, and as a
    # fallback for `max_age` enforcement when `auth_time_from_session` is
    # not configured.
    #
    # Example implementation:
    # resource_owner.current_sign_in_at
  end

  # Recommended: derive `auth_time` from the current session for `max_age`
  # enforcement. `auth_time_from_resource_owner` returns the same value for
  # every concurrent session of the same user (e.g. PC + smartphone), which
  # can let a stale session satisfy an RP's `max_age` requirement by
  # piggy-backing on a fresh login from another device.
  #
  # The block is executed in the controller's scope and receives the
  # current `session` and `request`. Return value can be a `Time`,
  # `DateTime`, or anything responding to `to_i`. Return `nil` to force
  # reauthentication.
  #
  # auth_time_from_session do |session, _request|
  #   # Example implementation: capture auth_time on the session at login,
  #   # and surface it here.
  #   session[:auth_time]
  # end

  # Advanced:
  # If you store `auth_time` in a custom authentication context record linked
  # to the access token, you can configure a block like below to derive it
  # from the access token instead of `auth_time_from_resource_owner`.
  #
  # This allows you to track `auth_time` per grant instead of per user,
  # but requires more custom implementation on your part.
  #
  # auth_time_from_access_token do |access_token|
  #   access_token.your_custom_authentication_context_record.auth_time
  # end

  reauthenticate_resource_owner do |resource_owner, return_to|
    # Example implementation:
    # store_location_for resource_owner, return_to
    # sign_out resource_owner
    # redirect_to new_user_session_url
  end

  select_account_for_resource_owner do |resource_owner_or_nil, return_to|
    # Example implementation:
    # if resource_owner_or_nil
    #   store_location_for resource_owner_or_nil, return_to
    # end
    # redirect_to account_select_url
  end

  subject do |resource_owner, _application|
    # Stable, opaque, globally-unique subject: the user's UUID. `sub` must be the same for
    # this resource owner across all clients of Dawa's own authorization server (we do not
    # use pairwise subject identifiers). A UUID is used rather than the integer primary key
    # so it doesn't leak user counts/ordering and stays stable across DB changes.
    resource_owner.uuid
  end

  # Protocol to use when generating URIs for the discovery endpoint (e.g. HTTPS in
  # production). Derived from the provider URL (see `issuer`) so the endpoints agree with it.
  protocol { URI.parse(Conf.openid_provider_url).scheme.to_sym }

  # Expiration time on or after which the ID Token MUST NOT be accepted for processing. (default 120 seconds).
  # expiration 600

  # Enable dynamic client registration (default false)
  # dynamic_client_registration true

  # Gate the dynamic client registration endpoint (RFC 7591 §3.1). Leave unset
  # (default `nil`) to keep the endpoint open once `dynamic_client_registration`
  # is enabled. Set a block to require authorization: it is evaluated in the
  # controller scope (so it can read `request`, `params`, `request.headers`,
  # etc.) and a falsy return rejects the request with `401 invalid_token`.
  #
  # authorize_dynamic_client_registration do
  #   # Example: require an Initial Access Token in the Authorization header.
  #   # Fail closed when the token isn't configured, so an unset env var can't
  #   # leave the endpoint open. Compare in constant time to avoid leaking the
  #   # token via timing; digesting first keeps the comparison fixed-length so
  #   # the token's length isn't leaked either.
  #   expected = ENV["DCR_INITIAL_ACCESS_TOKEN"].to_s
  #   next false if expected.empty?
  #
  #   provided = request.headers["Authorization"].to_s
  #   ActiveSupport::SecurityUtils.secure_compare(
  #     Digest::SHA256.hexdigest(provided),
  #     Digest::SHA256.hexdigest("Bearer #{expected}"),
  #   )
  # end

  # By default the `prompt` parameter (`none`, `login`, `consent`,
  # `select_account`) is only honored for OIDC requests (those carrying the
  # `openid` scope). Enable this to also honor `prompt` on non-OIDC
  # authorization requests. `max_age` stays OIDC-only, as it is defined by
  # OIDC Core.
  #
  # apply_prompt_to_non_oidc_requests true

  # End-session endpoint advertised in the discovery document
  # (`end_session_endpoint`). The block is evaluated in the controller scope;
  # return the absolute URL of your RP-initiated logout endpoint. Defaults to
  # `nil`, which omits the member from the discovery document.
  #
  # end_session_endpoint do
  #   end_session_url
  # end

  # Force every URL advertised in the discovery document to use the provider host, protocol,
  # and port (from Conf.openid_provider_url, the same value as `issuer`). This keeps
  # authorization_endpoint, token_endpoint, userinfo_endpoint, and jwks_uri consistent with
  # `issuer`, which strict OIDC clients require -- and reachable from the client (e.g. via
  # host.docker.internal when the client runs in a container). Keyed by endpoint.
  public_base = URI.parse(Conf.openid_provider_url)
  discovery_url_options do |_request|
    base = { host: public_base.host, protocol: public_base.scheme.to_sym }
    base[:port] = public_base.port if public_base.port != public_base.default_port
    {
      authorization: base,
      token: base,
      revocation: base,
      introspection: base,
      userinfo: base,
      jwks: base
    }
  end

  # You can use your own model class if you need to extend (or even override) the default
  # Doorkeeper::OpenidConnect::Request model (e.g. to use a different database connection).
  #
  # By default Doorkeeper OpenID Connect uses:
  #
  # open_id_request_class "Doorkeeper::OpenidConnect::Request"
  #
  # Don't forget to include the OpenID Connect ORM mixin into your custom model:
  #
  #   * ::Doorkeeper::OpenidConnect::Orm::ActiveRecord::Mixins::OpenidRequest
  #
  # For example:
  #
  # open_id_request_class "MyOpenidRequest"
  #
  # class MyOpenidRequest < ApplicationRecord
  #   include ::Doorkeeper::OpenidConnect::Orm::ActiveRecord::Mixins::OpenidRequest
  # end

  # Claims surfaced to /oauth/userinfo and, where configured, the ID Token.
  # Each is gated by the scope the client requested (see default_scopes/optional_scopes
  # in config/initializers/doorkeeper.rb).
  claims do
    normal_claim :preferred_username, scope: :username, response: %i[id_token user_info] do |resource_owner|
      resource_owner.username
    end

    normal_claim :given_name, scope: :username, response: %i[id_token user_info] do |resource_owner|
      resource_owner.display_name
    end

    normal_claim :email, scope: :email, response: %i[id_token user_info] do |resource_owner|
      resource_owner.email
    end

    normal_claim :is_admin, scope: :profile, response: %i[id_token user_info] do |resource_owner|
      resource_owner.is_admin?
    end
  end
end
