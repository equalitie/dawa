# Single Sign-On (SSO) / OpenID Connect in Dawa

This document covers how Dawa acts as an **OpenID Connect (OIDC) Identity Provider**
(OP / authorization server) built with **doorkeeper** + **doorkeeper-openid_connect**:
the OIDC login workflow, the configuration Dawa needs, and how to register an OIDC client
application. It ends with an overview of how doorkeeper was integrated.

Dawa authenticates its users **exclusively with WebAuthn/passkeys** — there is **no
password support**. Consequently the OIDC authorization server can never use the
resource-owner-password ("password") grant. The only way a user is established is through
their existing Dawa (WebAuthn) session.

## OIDC workflow

Dawa's OIDC provider is mounted under `/oauth` (via `use_doorkeeper` /
`use_doorkeeper_openid_connect` in `config/routes.rb`). A client application ("RP",
relying party) drives a user through the standard **authorization code + PKCE** flow.

### Browser/redirect sequence

1. A client app redirects the user's browser to Dawa's authorization endpoint:

   ```
   GET /oauth/authorize?response_type=code
                       &client_id=<client_uid>
                       &redirect_uri=<client_redirect_uri>
                       &scope=openid+username+email
                       &state=<client_state>
                       &code_challenge=<pkce_challenge>
                       &code_challenge_method=S256
   ```

   The browser sends Dawa's session cookie. `resource_owner_authenticator`
   (`config/initializers/doorkeeper.rb`) resolves the current user from
   `session[:user_id]`.

2. **Not logged in?** Dawa redirects the browser to its own login page (`/login`,
   the WebAuthn passkey prompt). After a successful passkey login the session cookie is
   set and the authorization request returns to Dawa's consent screen.

3. **Consent screen** — if the user is logged in, Dawa renders a consent page
   (`app/views/doorkeeper/authorizations/new.html.haml`) showing the requesting client
   name and the scopes it wants. The user clicks **Authorize** or **Deny**.

   - **Authorize** -> `POST /oauth/authorize` with the same parameters.
   - **Deny** -> `DELETE /oauth/authorize`.

4. Successful authorization issues an **authorization code** and redirects the browser
   back to the client:

   ```
   302 Location: https://client.example/callback?code=<one-time>&state=<client_state>
   ```

   With PKCE, the code is bound to the `code_challenge` sent in step 1.

5. The **client app** (server-side, not the user's browser) exchanges the code at the
   token endpoint:

   ```
   POST /oauth/token
   grant_type=authorization_code
   code=<code>
   redirect_uri=<client_redirect_uri>
   client_id=<client_uid>
   client_secret=<client_secret>     # confidential clients
   code_verifier=<pkce_verifier>     # must match the challenge from step 1
   ```

   Response contains `access_token`, `id_token`, `token_type`, and `scope`.

6. The client validates and can fetch claims:

   - **Discovery**: `GET /.well-known/openid-configuration` (issuer, endpoints, scopes).
   - **JWKS**: `GET /oauth/discovery/keys` (the RSA public key used to verify `id_token`
     signatures).
   - **UserInfo**: `GET /oauth/userinfo` with `Authorization: Bearer <access_token>`
     returns the granted claims (`sub`, `preferred_username`, `given_name`, `email`,
     `is_admin`).

### What is transmitted

| Step | Sent from -> to | Contents |
| --- | --- | --- |
| Authorize (browser) | browser -> Dawa | `client_id`, `redirect_uri`, `response_type=code`, `scope`, `state`, `code_challenge(_method)` (+ Dawa session cookie if present) |
| Unauthenticated redirect | Dawa -> browser | `302` to `/login` (WebAuthn passkey prompt) |
| Passkey login | browser <-> Dawa | WebAuthn assertion; Dawa sets its session cookie (`Set-Cookie`) |
| Consent (browser) | browser <-> Dawa | same authorize params, resolved from the user's session |
| Code redirect | Dawa -> browser -> client | one-time authorization `code`, `state` |
| Token exchange (server) | client -> Dawa | `code`, `redirect_uri`, `client_id`, `client_secret`, `code_verifier` |
| Token response (server) | Dawa -> client | `access_token`, `id_token`, `scope` |
| UserInfo (server) | client -> Dawa | `Authorization: Bearer <access_token>` |

No username or password ever crosses the wire at the OIDC layer; the user's identity is
established solely by the WebAuthn Dawa session.

## Configuration options needed in Dawa

### doorkeeper.rb

- `resource_owner_authenticator` — resolves the user from `session[:user_id]` (WebAuthn);
  otherwise redirects to `/login`. **This is the only way a resource owner is created.**
- `grant_flows [ "authorization_code" ]` — **no** `password` / `client_credentials`.
- `default_scopes :openid`
- `optional_scopes :username, :email, :profile, :offline_access`
- `force_pkce` — non-confidential clients must use PKCE.
- `hash_token_secrets` — access/refresh tokens stored as SHA-256 hashes.
- `hash_application_secrets` — client secrets stored hashed (plaintext shown once).
- `admin_authenticator` — restricts Doorkeeper's own `/oauth/applications` UI to admins.

### doorkeeper_openid_connect.rb

- `issuer "#{Conf.site_public_url}/oauth"`
- `signing_key File.read("config/oidc_signing_key.pem")` — a **3072-bit RSA private key**.
  This is a git-ignored secret; provision it per environment
  (`bundle exec rake oidc:generate_key`).
- `subject` — `resource_owner.id`.
- `resource_owner_from_access_token` — `User.find_by(id: token.resource_owner_id)`.
- `claims` — `preferred_username`, `given_name`, `email`, `is_admin`, each gated by scope.
- `protocol` / `discovery_url_options` — keep discovery URLs pinned to
  `Conf.site_public_url` so they agree with `issuer`.

`Conf` is provided by `config_magic` (`config/defaults.yml`, `config/config.yml` or env).
`site_public_url` drives the issuer and discovery endpoints.

### Signing key

```sh
bundle exec rake oidc:generate_key[config/oidc_signing_key.pem]   # 3072-bit RSA
bundle exec rake oidc:fingerprint[config/oidc_signing_key.pem]    # kid / fingerprint
```

## Registering an OIDC application

The OIDC provider is mounted at `/oauth` (set in `config/routes.rb`). The **issuer** and
**discovery URLs** are derived from `Conf.site_public_url` (see `config/defaults.yml`); to
point them at a public host, set `site_public_url` in an optional `config/config.yml`
override file or via the matching ENV var:

```yaml
  site_public_url: https://yoursso.example.com
```

### Variables needed to create a client application

Admin UI (`/settings/oauth-applications`) or via the console:

```ruby
Doorkeeper::Application.create!(
  name:         "My App",                          # human-readable display name
  redirect_uri: "https://myapp.example/callback",  # one URI per line, absolute HTTPS
  scopes:       "openid username email",           # space-separated; openid is required
  confidential: true                               # false for native/SPA clients (PKCE)
)
```

- **`name`** — shown on the consent screen.
- **`redirect_uri`** — must match exactly (no fragments; HTTPS in production).
- **`scopes`** — `openid` + any of `username`, `email`, `profile`, `offline_access`.
- **`confidential`** — `true` for server-side apps (uses `client_secret`); `false` for
  native/SPA (must use PKCE via `force_pkce`).
- Generated automatically: **`uid`** (client id) and **`secret`** (client secret; shown
  once at creation — it is stored hashed).

The client uses `uid`/`secret`, the issuer from discovery, and the JWKS to verify
`id_token` signatures.

## How doorkeeper is integrated in Dawa

Dawa uses gems **doorkeeper** (the OAuth2 authorization
server) and **doorkeeper-openid_connect** (the OIDC layer on top).

### Routes & migrations

- `rails generate doorkeeper:install`, `doorkeeper:openid_connect:install`
  (`config/routes.rb`: `use_doorkeeper`, `use_doorkeeper_openid_connect`,
  `mount Auth::Engine, at: "/auth"`).
- Migrations for `oauth_applications`, `oauth_access_grants`, `oauth_access_tokens`,
  `oauth_openid_requests` (sqlite-compatible).

### No-password design

Because there are no passwords:

- Only `authorization_code` is enabled as a grant flow.
- The `resource_owner_authenticator` reads `session[:user_id]` — the session key set by
  `Auth::SessionAuthentication#set_current_user!` during WebAuthn login. Unauthenticated
  visitors are bounced to `/login`. This is the only path to establishing a resource owner.
- Doorkeeper's public API controllers never go through Dawa's `ApplicationController`
  (which force-requires authentication) — only the interactive consent controller is
  Dawa-aware. This keeps `/oauth/token`, `/oauth/userinfo`, `/oauth/discovery/keys`, and
  `/.well-known/openid-configuration` reachable without a browser session.

### Custom consent screen

Doorkeeper's default consent UI was replaced with a minimal Dawa-styled Haml page (`app/views/doorkeeper/authorizations/new.html.haml`, rendered by
`app/controllers/oauth/authorizations_controller.rb` in a self-contained `oauth` layout).
It posts to `/oauth/authorize`.

### OIDC config

`config/initializers/doorkeeper_openid_connect.rb` wires the RSA `signing_key`, a stable
issuer derived from `Conf.site_public_url` (with discovery URLs pinned to the same value),
the `subject` (`user.id`), `resource_owner_from_access_token`, and scope-gated claims.

### Admin client management

A Dawa-shell admin CRUD (`app/controllers/oauth/applications_controller.rb`,
`/settings/oauth-applications`) manages `Doorkeeper::Application` records — list, create,
edit, revoke, and rotate client secrets. It is admin-only (`BaseAdminController`) and
avoids colliding with doorkeeper's own `/oauth/applications` routes. An "OAuth Apps" item
was added to the admin sidebar.

### Security hardening

- `force_pkce`, `hash_token_secrets`, `hash_application_secrets`.
- Admin-gated doorkeeper UI.

### Files that changed

| Area | Path |
| --- | --- |
| Gems | `Gemfile`, `Gemfile.lock` |
| Install/config | `config/initializers/doorkeeper.rb`, `config/initializers/doorkeeper_openid_connect.rb`, `config/locales/doorkeeper*.en.yml` |
| Routes | `config/routes.rb` |
| Migrations | `db/migrate/*create_doorkeeper*`, `*create_doorkeeper_openid_connect*` |
| Consent UI | `app/controllers/oauth/authorizations_controller.rb`, `app/views/doorkeeper/authorizations/new.html.haml`, `app/views/layouts/oauth.html.haml` |
| Admin clients | `app/controllers/oauth/applications_controller.rb`, `app/views/oauth/applications/*`, `app/helpers/sidebar_helper.rb` |
| Key tooling | `lib/tasks/oidc.rake` |
| Locale | `config/locales/en.yml` |
| Tests | `test/integration/oidc_flow_test.rb`, `oidc_consent_test.rb`, `oauth_applications_admin_test.rb` |


## Supporting password authentication

Dawa currently signs users in **only with WebAuthn/passkeys** (no passwords). If AuthApp eventually supports password login, only the **AuthApp login layer** needs real change -- the doorkeeper/OIDC integration described in this document is almost entirely agnostic to *how* a user ends up authenticated.

If passwords are added, an important choice is whether to also expose doorkeeper's OAuth `password` grant (Resource Owner Password Credentials).

The `password` grant allows a client application to collect username and password itself and then directly contact the identity provider. This exposes authentication credentials to the client application. For security reasons, and because we want to allow/require webauthn, Dawa does not support the `password` grant.
