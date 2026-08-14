Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :setup, only: [ :new, :create ], controller: "setup"
  get "up" => "rails/health#show", as: :rails_health_check

  root "feed#index"
  get "about", to: "pages#index", as: :about
  get "privacy_and_terms", to: "pages#privacy_and_terms"

  resources :links, only: [ :create ]
  resources :sources, only: [ :index, :show, :update ]
  resources :items, only: [ :update ] do
    member { get :player }
  end
end
