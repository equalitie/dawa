Rails.application.routes.draw do
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
  resources :invites
  resources :join, only: [:show, :update]

  resources :apps
  resources :catalog

  resources :backups, only: :index
  resources :containers
  get "containers/:id/stats", to: "container_stats#stats", as: :stats_container
  resources :logs, only: :index
  resource :metrics, only: :show do
    get :data
  end
  resource :troubleshoot, only: :show, controller: "troubleshoot"
  resource :settings, only: :show
  resource :profile, only: :show

  # OpenID Connect SSO
  use_doorkeeper do
    # override some doorkeeper controllers with our own:
    #   doorkeeper/oauth/authorizations => oauth/authorizations
    #   doorkeeper/oauth/applications => oauth/applications
    controllers(
      authorizations: "oauth/authorizations",
      applications: "oauth/applications"
    )
  end
  use_doorkeeper_openid_connect

  if Conf.demo
    namespace :demo do
      resource :session, only: [ :create, :update ]
    end
  end

  get "initials/:name", to: "initials#show", as: :initials
end
