class MarginAlertsController < ApplicationController
  def acknowledge
    @alert = Current.organization.margin_alerts.find(params[:id])
    @alert.acknowledge!(user: Current.user, notes: params[:notes])

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to alerts_path, notice: t("admin.margin_alerts.acknowledged") }
    end
  end

  def acknowledge_all
    Current.organization.margin_alerts.unacknowledged.find_each do |alert|
      alert.acknowledge!(user: Current.user)
    end

    redirect_to alerts_path, notice: t("admin.margin_alerts.all_acknowledged")
  end
end
