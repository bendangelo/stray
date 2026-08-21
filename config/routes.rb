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
  resources :collections do
    member do
      post :mark_read
    end
  end
  get "c/:slug", to: "collections#public_show", as: :public_collection
  get "c/:slug/manifest", to: "collections#manifest", as: :collection_manifest, defaults: { format: :json }
  get "c/:slug/feed", to: "collections#feed", as: :collection_feed, defaults: { format: :xml }
  resources :sources do
    member do
      post :pull
      post :mute
      post :unmute
      post :mark_read
      post :rotate_slug
    end
  end
  get "s/:slug",          to: "sources#public_show", as: :public_source
  get "s/:slug/feed",     to: "sources#feed",        as: :source_feed,     defaults: { format: :xml }
  get "s/:slug/manifest", to: "sources#manifest",    as: :source_manifest, defaults: { format: :json }
  resources :tags do
    member do
      patch :merge
    end
    collection do
      get :search
    end
  end
  resources :taggings, only: [ :create, :destroy ]
  resources :collection_memberships, only: %i[create destroy]
  resource :remote_collection, only: [:destroy]
  resources :items, only: [ :show, :update ] do
    member { get :player }
  end

  namespace :admin do
    get "/", to: "dashboard#index"
    resources :users, only: %i[index edit update destroy]
    resource :settings, only: %i[show update] do
      post :download_model
    end
    mount MissionControl::Jobs::Engine, at: "/jobs"
  end
end
