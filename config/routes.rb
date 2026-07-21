Rails.application.routes.draw do
  # OAuth provider — auth.buildcanada.com in production, /oauth/* in dev/test
  if Rails.env.production?
    constraints subdomain: "auth" do
      use_doorkeeper
    end
  else
    use_doorkeeper
  end

  # Sign in with LinkedIn (browser OmniAuth → Devise session) is used by the
  # Doorkeeper authorize flow so TradingPost readers can self-register and
  # engage with memos. The strategy is registered in config/initializers/devise.rb
  # and callbacks land in Users::OmniauthCallbacksController.
  devise_for :users, path: "", path_names: { sign_in: "login", sign_out: "logout" },
    controllers: {
      sessions: "users/sessions",
      passwords: "users/passwords",
      omniauth_callbacks: "users/omniauth_callbacks"
    },
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

      # OAuth userinfo / profile — the user behind the presented Doorkeeper token.
      resource :me, only: [ :show, :update ], controller: "me"

      resources :memos, param: :slug do
        resources :endorsements, only: [ :index, :create ]
        resources :critiques,    only: [ :index, :create ]
      end
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
        get "series", to: "series#index"
        resources :jurisdictions, only: [ :index, :show ], param: :slug do
          resources :organizations, only: [ :index, :show ], param: :slug
        end
        resources :organizations, only: [], param: :slug
        resources :measures, only: [ :index, :show ] do
          resources :facts, only: [ :index ]
          resources :citations, only: [ :index ]
          resources :compositions, only: [ :index ]
        end
        resources :compositions, only: [ :index ]
        resources :facts, only: [ :index ]
        resources :citations, only: [ :index ]
        resources :observations, only: [ :index, :show ] do
          member do
            get :derivations
          end
        end
        resources :documents, only: [ :index, :show ]
        resources :units, only: [ :index ]
        resources :organization_lineages, only: [ :index ]
        resources :measure_lineages, only: [ :index ]
        resources :agent_runs, only: [ :index, :show ]

        namespace :admin do
          resources :organizations, only: [ :create ]
          resources :units, only: [ :create ]
          resources :measures, only: [ :create ] do
            resources :footnote_links, only: [ :create, :destroy ], controller: "measure_footnotes"
          end
          resources :citations, only: [ :create ]
          resources :organization_lineages, only: [ :create ]
          resources :measure_lineages, only: [ :create ]
          resources :agent_runs, only: [ :create, :update, :show ]
          resources :review_queue, only: [ :index ]
          resources :extracted_observations, only: [] do
            member do
              post :approve
              post :reject
            end
            resources :review_flags, only: [ :create, :update ], controller: "observation_review_flags"
            resources :assertions, only: [ :create ], controller: "extraction_assertions"
            resources :footnote_links, only: [ :create, :destroy ], controller: "observation_footnotes"
          end
          resources :documents, only: [ :create ] do
            resources :footnotes, only: [ :create ], controller: "source_footnotes"
            member do
              post :archive
              get :archive, action: :archive_download
            end
          end
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

    namespace :kpis do
      resources :agent_runs, only: [ :index, :show ]
      resources :measures, only: [ :index, :show ]
      resources :citations, only: [ :index, :show ]
    end

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
    resources :critiques, only: [ :index, :show, :destroy ] do
      member do
        post :approve
        post :reject
      end
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
