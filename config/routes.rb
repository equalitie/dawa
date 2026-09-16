Rails.application.routes.draw do
  mount Auth::Engine, at: "/auth"
  mount RaftComponents::Engine, at: "/"

  resource :home, only: [ :show ], controller: "home"

  resource :enroll, only: [ :create, :update, :destroy ], controller: "enroll" do
    post :start
    get "(/:step)", action: :show, as: :step
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "root#show"

  resources :users
  resources :apps, only: :index
  resources :backups, only: :index
  resources :containers, only: :index
  resources :logs, only: :index
  resource :metrics, only: :show
  resource :troubleshoot, only: :show, controller: "troubleshoot"
  resource :settings, only: :show

  if Conf.demo
    namespace :demo do
      resource :session, only: [ :create, :update ]
    end
  end

  get "initials/:name", to: "initials#show", as: :initials
end
