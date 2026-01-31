module Webhooks
  class StripeController < ActionController::API
    def create
      payload = request.body.read
      sig_header = request.headers["Stripe-Signature"]
      webhook_secret = ENV["STRIPE_WEBHOOK_SECRET"]

      unless webhook_secret.present?
        head :service_unavailable
        return
      end

      event = ::Stripe::Webhook.construct_event(payload, sig_header, webhook_secret)

      case event.type
      when "customer.subscription.created",
           "customer.subscription.updated",
           "customer.subscription.deleted"
        handle_subscription_change(event)
      end

      head :ok
    rescue ::Stripe::SignatureVerificationError
      head :bad_request
    rescue JSON::ParserError
      head :bad_request
    end

    private

    def handle_subscription_change(event)
      stripe_account_id = event.account
      return unless stripe_account_id

      organization = Organization.find_by(stripe_user_id: stripe_account_id)
      return unless organization

      StripeSyncJob.perform_later(organization.id)
    end
  end
end
