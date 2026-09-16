# Single Sign-On (SSO) / OpenID Connect in Dawa

This document covers how Dawa acts as an **OpenID Connect (OIDC) Identity Provider**
(authorization server) built with **doorkeeper** + **doorkeeper-openid_connect**: the OIDC
login workflow, the configuration Dawa needs, how to register an OIDC client, the
cryptographic basis of trust, key pinning, and supported signing algorithms.

## OIDC key terms

- **IdP (Identity Provider) / OP (OpenID Provider)** -- the authorization server that authenticates users and issues tokens (Dawa, in our case).
- **RP (Relying Party)** -- the client application that delegates authentication to the IdP and validates the resulting tokens.
- **Authorization Code** -- a short-lived, one-time token issued after the user consents, exchanged by the RP for access/id tokens.
- **Access Token** -- grants the RP access to protected resources/APIs on the user's behalf.
- **ID Token** -- a signed JWT proving the user authenticated; carries identity claims (`sub`, `preferred_username`, `email`, etc.).
- **JWT (JSON Web Token)** -- the encoded token format (`header.payload.signature`) used for `id_token` and `access_token`.
- **JWS (JSON Web Signature)** -- the signature scheme JWT uses; provides authenticity/integrity.
- **JWKS (JSON Web Key Set)** -- the set of the IdP's public signing keys the RP uses to verify token signatures.
- **`sub` (Subject)** -- the unique, stable identifier for the end user.
- **Claims** -- key/value pairs about the user returned in tokens (e.g. `email`, `preferred_username`).
- **Scope** -- the set of permissions/claims a client requests (`openid`, `username`, `email`, `profile`, `offline_access`).
- **Grant / Grant Type** -- the flow by which tokens are obtained (e.g. authorization code, refresh, password).
- **Authorization Code + PKCE** -- the primary flow: code exchange bound to a `code_challenge`/`code_verifier` that prevents interception on public clients.
- **`iss` (Issuer)** -- the IdP's identifier; clients verify tokens carry the expected issuer.
- **`aud` (Audience)** -- the intended recipient; clients verify it matches their own `client_id`.
- **`exp` / `iat` / `nbf`** -- expiry, issued-at, and not-before timestamps.
- **`nonce`** -- a random value bound to the login session to prevent replay.
- **`state`** -- a client-generated value echoed back to prevent CSRF on the redirect.
- **`client_id`** -- the RP's public identifier registered with the IdP.
- **`client_secret`** -- the RP's shared secret used at the token endpoint for confidential clients.
- **Discovery** -- `/.well-known/openid-configuration`, which lists endpoints and supported features.
- **`kid` (Key ID)** -- identifies which JWK signed a token, enabling key rotation.
- **`alg`** -- the signature algorithm used (e.g. `RS256`, `ES256`).
- **Consent screen** -- the page where the user approves/denies a client's requested scopes.
- **ROPC / Password grant** -- a legacy flow where the client collects username/password directly; currently disabled for Dawa.

## OIDC workflow

Dawa's OIDC provider is mounted under `/oauth` (via `use_doorkeeper` /
`use_doorkeeper_openid_connect` in `config/routes.rb`). A client application ("RP",
relying party) drives a user through the standard **authorization code + PKCE** flow.

### Browser/redirect sequence

1. A Relaying Party redirects the user's browser to Dawa's authorization endpoint:

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

3. **Consent screen** -- if the user is logged in, Dawa renders a consent page
   (`app/views/doorkeeper/authorizations/new.html.haml`) showing the requesting client
   name (RP) and the scopes it wants. The user clicks **Authorize** or **Deny**.

   - **Authorize** -> `POST /oauth/authorize` with the same parameters.
   - **Deny** -> `DELETE /oauth/authorize`.

4. Successful authorization issues an **authorization code** and redirects the browser
   back to the RP:

   ```
   302 Location: https://client.example/callback?code=<one-time>&state=<client_state>
   ```

   With PKCE, the code is bound to the `code_challenge` sent in step 1.

5. The **Relaying Party** exchanges the code at the token endpoint:

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

6. The **Relaying Party** validates and can fetch claims:

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

## Configuration options needed in Dawa

### doorkeeper.rb

- `resource_owner_authenticator` -- resolves the user from `session[:user_id]` (WebAuthn);
  otherwise redirects to `/login`. **This is the only way a resource owner is created.**
- `grant_flows [ "authorization_code" ]` -- **no** `password` / `client_credentials`.
- `default_scopes :openid`
- `optional_scopes :username, :email, :profile, :offline_access`
- `force_pkce` -- non-confidential clients must use PKCE.
- `hash_token_secrets` -- access/refresh tokens stored as SHA-256 hashes.
- `hash_application_secrets` -- client secrets stored hashed (plaintext shown once).
- `admin_authenticator` -- restricts Doorkeeper's own `/oauth/applications` UI to admins.

### doorkeeper_openid_connect.rb

- `issuer "#{Conf.site_public_url}/oauth"`
- `signing_key File.read("config/oidc_signing_key.pem")` -- a **3072-bit RSA private key**.
  This is a git-ignored secret; provision it per environment
  (`bundle exec rake oidc:generate_key`).
- `subject` -- `resource_owner.id`.
- `resource_owner_from_access_token` -- `User.find_by(id: token.resource_owner_id)`.
- `claims` -- `preferred_username`, `given_name`, `email`, `is_admin`, each gated by scope.
- `protocol` / `discovery_url_options` -- keep discovery URLs pinned to
  `Conf.site_public_url` so they agree with `issuer`.

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

- **`name`** -- shown on the consent screen.
- **`redirect_uri`** -- must match exactly (no fragments; HTTPS in production).
- **`scopes`** -- `openid` + any of `username`, `email`, `profile`, `offline_access`.
- **`confidential`** -- `true` for server-side apps (uses `client_secret`); `false` for
  native/SPA (must use PKCE via `force_pkce`).
- Generated automatically: **`uid`** (client id) and **`secret`** (client secret; shown
  once at creation -- it is stored hashed).

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
- The `resource_owner_authenticator` reads `session[:user_id]` -- the session key set by
  `Auth::SessionAuthentication#set_current_user!` during WebAuthn login. Unauthenticated
  visitors are bounced to `/login`. This is the only path to establishing a resource owner.
- Doorkeeper's public API controllers never go through Dawa's `ApplicationController`
  (which force-requires authentication) -- only the interactive consent controller is
  Dawa-aware. This keeps `/oauth/token`, `/oauth/userinfo`, `/oauth/discovery/keys`, and
  `/.well-known/openid-configuration` reachable without a browser session.

### Custom consent screen

Doorkeeper's default consent UI was replaced with a minimal Dawa-styled Haml page at `app/views/doorkeeper/authorizations/new.html.haml`, rendered by `app/controllers/oauth/authorizations_controller.rb` in a self-contained `oauth` layout. It posts to `/oauth/authorize`.

### OIDC config

`config/initializers/doorkeeper_openid_connect.rb` wires the RSA `signing_key`, a stable
issuer derived from `Conf.site_public_url` (with discovery URLs pinned to the same value),
the `subject` (`user.id`), `resource_owner_from_access_token`, and scope-gated claims.

### Admin client management

A Dawa-shell admin CRUD (`app/controllers/oauth/applications_controller.rb`,
`/settings/oauth-applications`) manages `Doorkeeper::Application` records -- list, create,
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

The `password` grant allows a client application to collect username and password itself and then directly contact the identity provider, which exposes authentication credentials to the client application and bypasses Dawa's WebAuthn session and consent layers. For these reasons -- and because Dawa's security model is webauthn-based -- Dawa does not enable the `password` grant.

## Trust

The cryptographic trust in OIDC rests on **asymmetric key signatures** -- one party signs with a private key, the other verifies with the corresponding public key. Both directions of trust use the same JWT-signing mechanism but in opposite roles.

### IdP's public key

OIDC tokens (`id_token`, and by extension validated `access_token` as JWT) are **JWS (JSON Web Signature)** objects: a header + payload + signature. The signer produces the signature with a **private key**, and the verifier checks it with the matching **public key**.

The RP obtains the IdP public key in one of two ways:

* Pinned keys: The IdP's public key is preconfigured in the RP.
* Runtime discovery: The RP fetches the IdP's public key at runtime by reading the `jwks_uri` from the IdP's `/.well-known/openid-configuration` discovery document (or reading a configured `issuer`/`jwks_uri` directly) and then requesting that URL over TLS to receive the signing key material in a JSON Web Key Set (JWKS), which it uses to verify the `id_token` signature. This approach depends on the certificate authority as the trust anchor for validating the key. It supports **key rotation**: an IdP can publish a new key while retiring an old one, and RPs pick the right one per token.

### How the RP validates the IdP

This is the trust the user most often means -- the RP must prove the `id_token` actually came from IdP and wasn't forged/replayed.

1. **Signature verification.** The RP decodes the `id_token`, looks up the public key, and verifies the signature. Tampering is detectable because the attacker can't produce a valid signature without IdP's private key.

2. **Claim validation** (not cryptographic, but part of trust):
   - `iss` (issuer) must equal IdP's issuer (`https://.../oauth`) -- prevents a token minted by another IdP from being accepted.
   - `aud` (audience) must equal the RP's own `client_id` -- prevents a token meant for a *different* client from being reused.
   - `exp` / `nbf` / `iat` -- the token isn't expired or not-yet-valid.
   - `nonce` (if the RP sent one) -- binds the token to the specific login session and defeats replay.

### How the IdP validates the RP

IdP must prove the client is *allowed* before exchanging a code / issuing tokens. This uses **shared-secret (symmetric) authentication** for confidential clients, plus redirect-URI identity binding.

1. **Client authentication at the token endpoint.**
   `POST /oauth/token` requires the RP to authenticate itself with its credentials:
   - **Confidential clients:** `client_id` + `client_secret`. IdP compares the presented secret to the stored (hashed) secret -- a symmetric shared secret. (This is *not* public-key; it's a pre-shared secret IdP issued at registration.)
   - **Public clients (SPA/native):** no secret; instead they must present a valid **PKCE `code_verifier`** that matches the `code_challenge` the RP committed to at the authorization step.

2. **Authorization code binding.**
   The one-time `code` IdP issues is tied to the specific `client_id`, `redirect_uri`, and (for PKCE) `code_challenge` from the original authorize request. When the RP exchanges the code, IdP verifies:
   - the `client_id` is the same,
   - the `redirect_uri` matches the registered one,
   - the `code_verifier` (symmetric hash) matches. Only the RP that started the flow can complete it.

3. **Registration / redirect-URI allowlist.**
   IdP only talks to applications you registered. At authorize time, IdP checks the `redirect_uri` against the registered URI, so a token can't be redirected to an attacker's callback.

### Notes

The trust is not symmetric cryptographically: the RP authenticates IdP with **public-key signatures** (asymmetric), while Dawa authenticates the RP with **shared secrets / lookups** (symmetric). That asymmetry is conventional in OIDC -- the IdP's identity is long-lived and public (so a public key works), whereas each RP's identity is private to it and IdP (so a secret makes sense).

## IdP Signing-Key Pinning

Instead of fetching the IdP's signing key at runtime (via OIDC discovery + JWKS over HTTPS), an RP is **pre-provisioned** with the IdP's public key. It validates `id_token` signatures locally against that pinned key and never relies on the network (or TLS) to learn "which key is the IdP's."

### Benefits

OWASP's OIDC guidance recommends not trusting a dynamically-retrieved key without additional assurance. The threat is that a compromised CA chain, a hijacked/MITM'd connection, or a compromised or malicious discovery/JWKS endpoint can substitute a rogue public key. If the RP trusts the key it just fetched, the attacker can mint `id_token`s that verify successfully. Pinning breaks that: the RP already knows the correct key and rejects any key (e.g., a different `kid`) it wasn't given ahead of time -- turning key discovery from a trust-on-first-use problem into a known-good comparison.

### Downsides

- **Rotation cost/tight coupling:** IdP key rotation breaks pinned RPs until every client is updated -- rotation requires coordinated rollout (or a window where both old+new keys are trusted).
- **Key-management surface:** the pinned key/material must be provisioned securely and kept correct on the RP side.
- **Does not replace TLS:** pinning proves token *authenticity*; it doesn't encrypt traffic or stop information disclosure. A compromised connection corrupting the authorization code or `access_token` is not prevented.
- **Single point of lock-in:** a pinned RP is permanently coupled to that IdP's public identity until re-provisioned.

### Generating public key pins

Different RPs will support different forms to express a pin of the same IdP RSA public key. 

#### PEM / Certificates

```sh
bundle exec rails runner 'puts OpenSSL::PKey::RSA.new(File.read("config/oidc_signing_key.pem")).public_key.to_pem' > config/oidc_signing_key.pub.pem
```

#### JWKS File

```sh
bundle exec rails runner 'puts Doorkeeper::OpenidConnect.signing_keys_normalized.to_json' > config/oidc_signing_jwks.json
```

#### Allowed fingerprint

To print the `kid` (SHA-256 of the public key DER) and SHA-1 fingerprint of the signing key:

```sh
bundle exec rake "oidc:fingerprint[config/oidc_signing_key.pem]"
```

The `kid` is the same value Dawa's JWKS advertises, so an RP can whitelist exactly that `kid` as an additional sanity check (or on its own if the client only accepts a fingerprint).

### Rotation

If the app supports it, publish the retired `kid`'s public key alongside the new one (e.g., the JWKS can list both) so pinned RPs can migrate rather than hard-fail on rotation.

## Other Key Algorithms

OIDC supports three families of signing keypairs (`id_token_signing_alg_values_supported`):

**RSA family**
- `RS256`, `RS384`, `RS512` -- RSA + PKCS#1 v1.5 (`RS256` is the near-universal default).

**EC (Elliptic Curve) family** -- this is the realistic alternative to RSA today
- `ES256` (P-256), `ES384` (P-384), `ES512` (P-512) -- ECDSA. Much smaller keys, faster verification, increasingly the modern default.

**EdDSA**
- `EdDSA` / `Ed25519` -- used by some newer providers; compact and fast.

It would be nice to switch to EC or EdDSA, but support is not universal across RPs. To migrate, you can configure doorkeeper with an **array** of signing keys (`signing_key [rsa_pem, ec_pem, ...]`): the first entry signs new ID tokens, while every entry is published in the JWKS its own `kid`. That lets you (1) run a key-rotation window where both old and new keys verify, and (2) gradually move clients from `RS256` to `ES256`/`EdDSA` -- so adding a second key alongside RSA does give a real benefit during a migration.

## Confidential Clients versus Public Clients

There are two types of relaying parties with OIDC: confidential clients and public clients.

* Confidential clients: there is a registered client_id and shared client_secret is used to confirm the client's identity. PKCE is optional.
* Public clients: there is a registered client_id but no client_secret. PKCE is required.

Both confidential and public clients are **pre-registered** with the IdP and receive a `client_id` (the doorkeeper `Doorkeeper::Application` record). Registration includes the name, the exact `redirect_uri`, and the requested scopes. The only difference is whether the client is also issued a shared `client_secret` that it can keep private.

- A **confidential client** gets a `client_id` and a `client_secret`. It runs on a server (backend) where the secret can be stored safely and never shipped to end users.

- A **public client** gets a `client_id` but **no usable secret**. It runs in the browser (SPA) or on a device (native/mobile app), where any embedded secret would be extractable, so it is not given one to protect. Anyone can impersonate the client.

In both cases, the client_id is public (easily obtained).

### How user identity is proven

**Confidential Client (authorization code flow):** After the user has authenticated with the IdP and the IdP has replied with authorization `code`, the RP contacts the IdP's token endpoint directly over TLS  presenting `code`, `client_id` and `client_secret`. IdP verifies the secret against the stored (hashed) `client_secret`, then responds with an access token and identity token `id_token`.

**Public Client (authorization code + PKCE):**
the client (RP) starts the flow by opening a browser window that makes an authorize request of the IdP, presenting `client_id` and `code_challenge` (hash of private `code_verifier`). After the user authenticates and IdP gives RP the authorization `code`, the RP then calls the token endpoint directly, sending the `code` **plus** the now-revealed `code_verifier`. The IdP hashes the verifier and checks it matches the stored challenge, then responds with an access token and identity token `id_token`.

### PKCE

Here are some more details on PKCE. 

PKCE (Proof Key for Code Exchange) protects the **authorization code** from interception, so a malicious third party cannot steal a code and redeem it to impersonate a user. It works by binding a code to the party that started the flow:

1. The client generates a random, high-entropy **code_verifier** and keeps it private.
2. It sends only a one-way derivation of it, the **code_challenge**, in the authorize
   request (`code_challenge_method=S256` means SHA-256 hashing).
3. IdP issues a code bound to that challenge.
4. To exchange the code, the client must send the matching **code_verifier**.
5. IdP hashes the verifier and checks it matches the stored challenge. Only the client that generated the verifier can redeem the code - an interceptor without the verifier is rejected with `invalid_grant`.

Important limits of PKCE:

- It prevents **code interception / replay** and lets a **public** client show continuity
  with the party that started the flow.
- It does **not** prove the client's identity. A public client is still "anyone claiming
  this client_id"; PKCE means the same party started and finished the flow, nothing more.

### When each is used

- PKCE is **required** for non-confidential clients. In Dawa this is enforced by
  `force_pkce` - a public client that exchanges a code without a valid `code_verifier` is
  rejected.
- PKCE is **optional** for confidential clients, which can authenticate with their
  `client_secret` instead. Adding PKCE on top is recommended as defense-in-depth, since it
  prevents code interception even if the secret is somehow exposed.

### Security implications

- A leaked confidential secret lets an attacker impersonate that specific client (complete
  its exchanges and use its refresh tokens) - a **client-identity** compromise, gated by
  the user still needing to authorize.
- A public client has no secret to leak, but it also has no real identity credential.
  `redirect_uri` exact-match validation, `state`, and PKCE are its only binding.
- Long-lived `refresh_token` / `offline_access` is riskier for public clients: they store
  tokens in browser storage / keychain (exposed to XSS or device theft) and cannot
  re-authenticate with a secret. Reserve `offline_access` for confidential clients where
  possible.

### Summary

- Set `confidential: true` for any server-side app and guard the `client_secret` server-side.
- Set `confidential: false` only for browser or native apps, and rely on `force_pkce` and a
  strict, exact `redirect_uri`.
- Never embed a confidential secret in an SPA or mobile app.
- Do not hand `offline_access` / refresh tokens to public clients if you can avoid it.
