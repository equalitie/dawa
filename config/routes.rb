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

  resources :apps, only: [ :index, :show, :update ] do
    # Jobs are nested bc they are only valid in context of an instance.
    # constraint is require for ":" chars in job id
    resources :jobs, only: :show, controller: "app_jobs", constraints: { id: /[^\/]+/ }

    # Uninstalling: the confirmation page, then the removal itself. Confirming is typing the
    # instance name (see AppsController#destroy), so the removal has to be a form submission and
    # not something a stray GET could trigger.
    member do
      get :uninstall
    end
    delete "uninstall", to: "apps#destroy"
  end

  resources :catalog, only: [ :index, :show ] do
    member do
      get :install, to: "app_installs#new"
    end
  end
  post "apps/install", to: "app_installs#create", as: :install_app

  resources :backups, only: :index
  resources :containers
  get "containers/:id/stats", to: "container_stats#stats", as: :stats_container
  resources :logs, only: :index do
    # JSON refresh endpoint. Named explicitly so it does not collide with the
    # `data` member route the singular `resource :metrics` below generates.
    get :data, on: :collection, as: :data
  end
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
