Rails.application.routes.draw do
  mount RaftComponents::Engine, at: "/"

  # Root route needed for ActionView URL helpers
  root to: "home#show"
end
