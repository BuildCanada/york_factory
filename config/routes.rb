Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    namespace :v1 do
      resources :organizations, only: [:index, :show]
      resources :deviations, only: [:index]
      resource :query, only: [:create]
    end
  end

  mount MissionControl::Jobs::Engine, at: "/jobs"

  namespace :admin do
    get "/", to: "dashboard#index"
    get "ingestions", to: "dashboard#ingestions"
    get "lineage_review", to: "dashboard#lineage_review"
  end
end
