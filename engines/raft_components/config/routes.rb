RaftComponents::Engine.routes.draw do
  get "initials/:name", to: "initials#show", as: :initials
end
