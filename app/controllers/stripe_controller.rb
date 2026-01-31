class StripeController < ApplicationController
  def connect
    state = SecureRandom.hex(32)
    session[:stripe_oauth_state] = state

    authorize_url = "https://connect.stripe.com/oauth/authorize?" + {
      response_type: "code",
      client_id: ENV.fetch("STRIPE_CLIENT_ID"),
      scope: "read_only",
      redirect_uri: stripe_callback_url,
      state: state
    }.to_query

    redirect_to authorize_url, allow_other_host: true
  end

  def callback
    unless ActiveSupport::SecurityUtils.secure_compare(params[:state].to_s, session.delete(:stripe_oauth_state).to_s)
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

    StripeSyncJob.perform_later(organization.id)

    redirect_to settings_path, notice: t("controllers.stripe.connected")
  rescue Stripe::StripeError => e
    Rails.logger.error("Stripe OAuth error: #{e.class} - #{e.message}")
    redirect_to settings_path, alert: t("controllers.stripe.error")
  end

  def sync
    organization = Current.organization
    unless organization.stripe_user_id.present?
      redirect_to settings_path, alert: t("controllers.stripe.error")
      return
    end

    StripeSyncJob.perform_later(organization.id)
    redirect_to settings_path, notice: t("controllers.stripe.sync_complete")
  end

  def disconnect
    organization = Current.organization

    if organization.stripe_user_id.present?
      begin
        Stripe::OAuth.deauthorize(stripe_user_id: organization.stripe_user_id)
      rescue Stripe::StripeError => e
        Rails.logger.error("Stripe deauthorize error: #{e.message}")
      end
    end

    organization.update!(stripe_user_id: nil, stripe_access_token: nil)
    redirect_to settings_path, notice: t("controllers.stripe.disconnected")
  end
end
