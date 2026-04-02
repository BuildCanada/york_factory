Rails.application.routes.draw do
  devise_for :users, skip: :all
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :organizations, only: [ :index, :show ]
      resources :deviations, only: [ :index ]

      namespace :auth do
        post "google", to: "sessions#create"
        delete "session", to: "sessions#destroy"
      end

      resources :memos, param: :slug
      resources :posts, param: :slug
      resources :builders, param: :slug
      resources :team_members, path: "team" do
        put :bulk_update, on: :collection
      end
      resources :tools do
        put :bulk_update, on: :collection
      end
      resources :faqs do
        put :bulk_update, on: :collection
      end
      resources :feed_items, path: "feed"
      resources :testimonials do
        put :bulk_update, on: :collection
      end
      resources :subscribers, only: [ :create ]
      resources :uploads, only: [ :create ]
    end
  end

  namespace :admin do
    authenticate = ->(request) {
      user_id = request.session[:admin_user_id]
      user_id && User.find_by(id: user_id)&.admin?
    }
    constraints(authenticate) do
      mount MissionControl::Jobs::Engine, at: "jobs"
    end

    full = %i[index show new create edit update destroy]

    get "login", to: "sessions#new", as: :login
    post "login", to: "sessions#create"
    match "logout", to: "sessions#destroy", as: :logout, via: [ :get, :delete ]

    get "/", to: "dashboard#index", as: :root
    get "ingestions", to: "dashboard#ingestions"
    get "lineage_review", to: "dashboard#lineage_review"
    post "webflow_sync", to: "dashboard#webflow_sync"

    resources :posts, only: full do
      post :retranslate, on: :member
    end
    resources :memos, only: full do
      post :retranslate, on: :member
    end
    resources :builders, only: full do
      post :retranslate, on: :member
    end
    resources :team_members, only: full do
      put :reorder, on: :collection
      post :retranslate, on: :member
    end
    resources :tools, only: full do
      put :reorder, on: :collection
      post :retranslate, on: :member
    end
    resources :faqs, only: full do
      put :reorder, on: :collection
      post :retranslate, on: :member
    end
    resources :feed_items, only: full do
      post :retranslate, on: :member
    end
    resources :testimonials, only: full do
      put :reorder, on: :collection
      post :retranslate, on: :member
    end
    resources :subscribers, only: [ :index ]
  end
end
