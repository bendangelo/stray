Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :setup, only: [ :new, :create ], controller: "setup"
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "feed#index"
  get "search/suggest", to: "search#suggest", as: :search_suggest
  get "about", to: "pages#index", as: :about
  get "privacy_and_terms", to: "pages#privacy_and_terms"

  resources :links, only: [ :create ] do
    collection do
      post :bulk_create
    end
  end
  resources :collections
  get "c/:slug", to: "collections#public_show", as: :public_collection
  get "c/:slug/manifest", to: "collections#manifest", as: :collection_manifest, defaults: { format: :json }
  get "c/:slug/feed", to: "collections#feed", as: :collection_feed, defaults: { format: :xml }
  resources :sources do
    member do
      post :pull
    end
  end
  resources :tags do
    member do
      patch :merge
    end
    collection do
      get :search
    end
  end
  resources :taggings, only: [ :create, :destroy ]
  resource :remote_collection, only: %i[new create destroy] do
    post :subscribe
  end
  resources :items, only: [ :update ] do
    member { get :player }
  end

  namespace :admin do
    resource :settings, only: %i[show update] do
      post :download_model
    end
  end
end
