Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#index"
  get "privacy_and_terms", to: "pages#privacy_and_terms"
end
