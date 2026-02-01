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
      when "invoice.paid"
        handle_invoice_paid(event)
      when "invoice.payment_failed"
        handle_invoice_payment_failed(event)
      when "customer.subscription.deleted"
        handle_subscription_deleted(event)
      end

      head :ok
    rescue ::Stripe::SignatureVerificationError
      head :bad_request
    rescue JSON::ParserError
      head :bad_request
    end

    private

    def handle_invoice_paid(event)
      stripe_account_id = event.account
      return unless stripe_account_id

      organization = Organization.find_by(stripe_user_id: stripe_account_id)
      return unless organization

      invoice = event.data.object
      Stripe::InvoiceSyncService.new(organization).upsert_single_invoice(invoice)
    end

    def handle_invoice_payment_failed(event)
      stripe_account_id = event.account
      return unless stripe_account_id

      organization = Organization.find_by(stripe_user_id: stripe_account_id)
      return unless organization

      invoice = event.data.object
      Rails.logger.warn("Stripe invoice payment failed: #{invoice.id} for org #{organization.id}")
    end

    def handle_subscription_deleted(event)
      stripe_account_id = event.account
      return unless stripe_account_id

      organization = Organization.find_by(stripe_user_id: stripe_account_id)
      return unless organization

      subscription = event.data.object
      Rails.logger.info("Stripe subscription deleted: #{subscription.id} for org #{organization.id}")
    end
  end
end
