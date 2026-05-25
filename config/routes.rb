Rails.application.routes.draw do
  devise_for :users, path: "", path_names: { sign_in: "login", sign_out: "logout" },
    controllers: { sessions: "users/sessions", passwords: "users/passwords" },
    skip: [ :registrations, :confirmations, :unlocks ]

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
      resources :feed_entries, path: "feed", only: [ :index, :show ] do
        get :picks, on: :collection
      end
      resources :testimonials do
        put :bulk_update, on: :collection
      end
      resources :subscribers, only: [ :create ]
      resources :uploads, only: [ :create ]

      namespace :geo do
        get "crosswalk", to: "crosswalk#show"
        get "boundaries", to: "boundaries#index"
        get "addresses", to: "addresses#index"
      end

      namespace :trade_barriers do
        resources :agreements, only: [ :index, :show ], param: :slug
        resources :themes, only: [ :index ]
      end

      namespace :warehouse do
        resources :jurisdictions, only: [ :index ]
      end

      namespace :kpis do
        resources :jurisdictions, only: [ :index, :show ], param: :slug do
          resources :organizations, only: [ :index, :show ], param: :slug
        end
        resources :organizations, only: [], param: :slug
        resources :measures, only: [ :index, :show ] do
          resources :facts, only: [ :index ]
          resources :citations, only: [ :index ]
        end

        namespace :admin do
          resources :documents, only: [ :create ]
          resources :measures, only: [ :create ]
          resources :citations, only: [ :create ]
          resources :organization_lineages, only: [ :create ]
          resources :measure_lineages, only: [ :create ]
        end
      end
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
    resources :feed_entries, only: [ :index, :edit, :update ] do
      post :retranslate, on: :member
    end
    resources :testimonials, only: full do
      put :reorder, on: :collection
      post :retranslate, on: :member
    end
    resources :subscribers, only: [ :index ]
    resources :users, only: %i[index new create edit update destroy]

    namespace :metrics do
      get "/", to: "overview#index", as: :root
      resources :twitter_stats, only: [ :index ] do
        post :import, on: :collection
      end
      resources :linkedin_stats, only: [ :index ] do
        post :import, on: :collection
      end
      resources :substack_stats, only: [ :index ] do
        post :import, on: :collection
      end
      resources :tiktok_stats, only: [ :index ] do
        post :import, on: :collection
      end
      resources :instagram_stats, only: %i[index new create edit update destroy] do
        post :generate_weeks, on: :collection
      end
    end

    namespace :trade_barriers do
      resources :agreements, only: full
      resources :themes, only: full
    end
  end

  # Member profile
  get "profile", to: "profile#show", as: :profile
  patch "profile", to: "profile#update"
end
