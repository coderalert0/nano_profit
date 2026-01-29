Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[ new create ]

  namespace :api do
    namespace :v1 do
      resources :telemetry_events, only: :create
    end
  end

  namespace :admin do
    resources :vendor_rates
    resources :margin_alerts, only: [] do
      member do
        patch :acknowledge
      end
      collection do
        patch :acknowledge_all
      end
    end
  end

  root "dashboard#show"

  resource :dashboard, only: :show, controller: "dashboard"
  resources :customers, only: %i[ index show ]
  resources :events, only: :index
  resources :alerts, only: %i[ index ]
  resource :settings, only: %i[ show update ] do
    post :regenerate_api_key, on: :member
  end
  resource :documentation, only: :show, controller: "documentation"

  get "stripe/connect", to: "stripe#connect", as: :stripe_connect
  get "stripe/callback", to: "stripe#callback", as: :stripe_callback
  post "stripe/sync", to: "stripe#sync", as: :stripe_sync
  delete "stripe/disconnect", to: "stripe#disconnect", as: :stripe_disconnect

  get "up" => "rails/health#show", as: :rails_health_check
end
