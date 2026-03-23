Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :government_entities, only: [:index, :show]
      resources :corporate_entities, only: [:index, :show] do
        member do
          get :directors
        end
      end
      resources :corporate_directors, only: [] do
        member do
          get :entities
        end
      end
      resources :business_establishments, only: [:index, :show]
      resources :deviations, only: [:index]
      resource :query, only: [:create]
    end
  end

  mount MissionControl::Jobs::Engine, at: "/jobs"

  namespace :admin do
    get "/", to: "dashboard#index"
    get "ingestions", to: "dashboard#ingestions"
    get "lineage_review", to: "dashboard#lineage_review"
    post "ingest/:source_name", to: "dashboard#trigger_ingest", as: :trigger_ingest
    post "ingest_all", to: "dashboard#trigger_ingest_all", as: :trigger_ingest_all
  end
end
