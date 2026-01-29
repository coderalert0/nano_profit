class StripeController < ApplicationController
  def connect
    authorize_url = "https://connect.stripe.com/oauth/authorize?" + {
      response_type: "code",
      client_id: ENV.fetch("STRIPE_CLIENT_ID"),
      scope: "read_only",
      redirect_uri: stripe_callback_url,
      state: form_authenticity_token
    }.to_query

    redirect_to authorize_url, allow_other_host: true
  end

  def callback
    unless valid_authenticity_token?(session, params[:state])
      redirect_to settings_path, alert: t("controllers.stripe.error")
      return
    end

    response = Stripe::OAuth.token(
      grant_type: "authorization_code",
      code: params[:code]
    )

    organization = Current.organization
    organization.update!(
      stripe_user_id: response.stripe_user_id,
      stripe_access_token: response.access_token
    )

    Stripe::SubscriptionSyncService.new(organization).sync

    redirect_to settings_path, notice: t("controllers.stripe.connected")
  rescue Stripe::OAuth::InvalidGrantError, Stripe::StripeError => e
    Rails.logger.error("Stripe OAuth error: #{e.message}")
    redirect_to settings_path, alert: t("controllers.stripe.error")
  end

  def sync
    organization = Current.organization
    unless organization.stripe_user_id.present?
      redirect_to settings_path, alert: t("controllers.stripe.error")
      return
    end

    Stripe::SubscriptionSyncService.new(organization).sync
    redirect_to settings_path, notice: t("controllers.stripe.sync_complete")
  end

  def disconnect
    organization = Current.organization
    organization.update!(stripe_user_id: nil, stripe_access_token: nil)
    redirect_to settings_path, notice: t("controllers.stripe.disconnected")
  end
end
