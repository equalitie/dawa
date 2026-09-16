Rails.application.routes.draw do
  resource :home, only: [ :show ], controller: "home"
  resource :test_session, only: [ :create, :update ]

  mount Auth::Engine,   at: "/auth"
end
