class AlertsController < ApplicationController
  def index
    @alerts = Current.organization.margin_alerts.recent.includes(:customer)
  end

  def acknowledge
    alert = Current.organization.margin_alerts.find(params[:id])
    alert.acknowledge!
    redirect_to alerts_path, notice: "Alert acknowledged."
  end
end
