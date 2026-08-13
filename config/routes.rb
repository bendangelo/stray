Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :setup, only: [ :new, :create ], controller: "setup"
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#index"
  get "privacy_and_terms", to: "pages#privacy_and_terms"
end
