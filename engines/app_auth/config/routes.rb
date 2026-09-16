Auth::Engine.routes.draw do
  resource :session, only: [ :new, :destroy ] do
    post :initiate
    post :verify
    get :phrase
    post :phrase
  end

  resource :recover, only: [ :create, :show ]

  scope controller: "webauthn" do
    post "webauthn/register_initiate"
    post "webauthn/register_verify"
    post "webauthn/authenticate_initiate"
    post "webauthn/authenticate_verify"
  end

  resources :credentials
  resource :anonymous, only: [ :edit, :update ]
end
