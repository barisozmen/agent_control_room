Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "dashboards#show"

  resources :runs, only: %i[create show] do
    resources :passports, only: :show
    resources :audit_events, only: :index
    resources :tool_actions, only: :index
  end

  resources :permission_requests, only: :show do
    resources :decisions, only: :create, controller: "permission_decisions"
  end

  resources :runtime_events, only: :create
  post "runtime/:runtime_name/events" => "runtime_observer_events#create", as: :runtime_observer_events
  post "opencode/events" => "opencode_events#create", as: :opencode_events
end
