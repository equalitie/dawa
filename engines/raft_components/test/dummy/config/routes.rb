Rails.application.routes.draw do
  # Root route needed for ActionView URL helpers
  root to: "home#show"
end
