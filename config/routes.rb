Rails.application.routes.draw do
  devise_for :users, path: "", path_names: { sign_in: "login", sign_out: "logout" },
    controllers: { sessions: "users/sessions" },
    skip: [ :registrations, :passwords, :confirmations, :unlocks ]

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
    superadmin_only = ->(request) {
      user = request.env["warden"].user(:user)
      user&.superadmin?
    }
    constraints(superadmin_only) do
      mount MissionControl::Jobs::Engine, at: "jobs"
    end

    full = %i[index show new create edit update destroy]

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
    resources :users, only: %i[index new create edit update destroy]

    namespace :metrics do
      resources :twitter_stats, only: [ :index ] do
        post :import, on: :collection
      end
    end
  end

  # Member profile
  get "profile", to: "profile#show", as: :profile
  patch "profile", to: "profile#update"
end
