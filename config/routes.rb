Rails.application.routes.draw do
  use_doorkeeper do
    # Render Doorkeeper's consent screen with Dawa's controller, layout, and WebAuthn
    # session (see app/controllers/oauth/authorizations_controller.rb). Public API
    # endpoints kept on Doorkeeper defaults.
    controllers authorizations: "oauth/authorizations"
  end
  use_doorkeeper_openid_connect
  mount Auth::Engine, at: "/auth"
  mount RaftComponents::Engine, at: "/"

  resource :home, only: [ :show ], controller: "home"
  resource :dashboard, only: [ :show ], controller: "dashboard"

  resource :enroll, only: [ :create, :update, :destroy ], controller: "enroll" do
    post :start
    get "(/:step)", action: :show, as: :step
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "root#show"
  get "login" => "root#login"

  resources :users
  resources :apps, only: :index
  resources :backups, only: :index
  resources :containers, only: [ :index, :show, :update ]
  get "containers/:id/stats", to: "container_stats#stats", as: :stats_container
  resources :logs, only: :index
  resource :metrics, only: :show
  resource :troubleshoot, only: :show, controller: "troubleshoot"
  resource :settings, only: :show
  resource :profile, only: :show

  # Admin CRUD for Doorkeeper OIDC client applications (see app/controllers/oauth/applications_controller.rb).
  # Path is under /settings to avoid colliding with Doorkeeper's own /oauth routes; `as:`
  # avoids the `oauth_application(s)` helper names Doorkeeper already claims.
  resources :oauth_applications,
            path: "settings/oauth-applications",
            controller: "oauth/applications",
            as: :settings_oauth_applications do
    member { patch :rotate }
  end

  if Conf.demo
    namespace :demo do
      resource :session, only: [ :create, :update ]
    end
  end

  get "initials/:name", to: "initials#show", as: :initials
end
