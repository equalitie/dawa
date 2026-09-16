#
# Dawa's override of Doorkeeper's OAuth consenter / authorization screen.
#
# The default Doorkeeper UI is JQuery-heavy; we render a minimal Dawa-styled consent
# page instead, in Dawa's self-contained `oauth` layout, and identify the user from the
# WebAuthn session. Authentication itself is handled by Doorkeeper's own
# `authenticate_resource_owner!` before_action, which evaluates the
# resource_owner_authenticator we configured to read session[:user_id] (the WebAuthn
# session) — so this API stays password-free.
#
# IMPORTANT: we deliberately do NOT set Doorkeeper.config.base_controller to Dawa's
# `ApplicationController`. That class runs `require_authentication` on every action and
# would lock down doorkeeper's PUBLIC endpoints (/oauth/token, /oauth/userinfo,
# /oauth/discovery/keys, /.well-known/openid-configuration) which client applications
# call without a browser session. So Dawa's session layer is wired in for the interactive
# consent screen only, via `controllers` in the `use_doorkeeper` route block.
#
module Oauth
  class AuthorizationsController < ::Doorkeeper::AuthorizationsController
    helper_method :current_user

    def current_user
      @current_user ||= User.find_by(id: session[:user_id])
    end

    # Dawa's consent layout (app/views/layouts/oauth.html.haml) is a self-contained,
    # branded bootstrap shell rendered via the layout engine's `inset` template. It does
    # NOT pull in Dawa's admin sidebar / session header, which depend on auth-engine
    # helpers (logout_button, sidebar_items, v) that are unavailable to doorkeeper
    # controllers. This keeps the consent screen decoupled and robust.
    layout "oauth"
  end
end
