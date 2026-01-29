Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[ new create ]

  namespace :api do
    namespace :v1 do
      resources :telemetry_events, only: :create
    end
  end

  root "dashboard#show"

  resource :dashboard, only: :show, controller: "dashboard"
  resources :customers, only: %i[ index show ]
  resources :alerts, only: %i[ index ] do
    member do
      patch :acknowledge
    end
  end
  resource :settings, only: %i[ show update ] do
    post :regenerate_api_key, on: :member
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
