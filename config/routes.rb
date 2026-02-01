Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[ new create ]
  get "verify_email", to: "email_verifications#show", as: :verify_email

  namespace :api do
    namespace :v1 do
      resources :events, only: :create
    end
  end

  namespace :webhooks do
    resource :stripe, only: :create, controller: "stripe"
  end

  namespace :admin do
    resources :vendor_rates
    resources :price_drifts, only: [:index] do
      member do
        patch :apply
        patch :ignore
      end
      collection do
        patch :update_threshold
      end
    end
  end

  resources :margin_alerts, only: [] do
    member do
      patch :acknowledge
    end
    collection do
      patch :acknowledge_all
    end
  end

  root "pages#home"

  resource :dashboard, only: :show, controller: "dashboard"
  resources :customers, only: %i[ index show ]
  resources :events, only: :index
  resources :event_types, only: :index
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
