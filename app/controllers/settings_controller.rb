class SettingsController < ApplicationController
  def show
    @organization = Current.organization
  end

  def update
    @organization = Current.organization
    if @organization.update(organization_params)
      redirect_to settings_path, notice: t("controllers.settings.updated")
    else
      render :show, status: :unprocessable_entity
    end
  end

  def regenerate_api_key
    Current.organization.regenerate_api_key!
    redirect_to settings_path, notice: t("controllers.settings.api_key_regenerated")
  end

  private

  def organization_params
    params.require(:organization).permit(:margin_alert_threshold_bps)
  end
end
