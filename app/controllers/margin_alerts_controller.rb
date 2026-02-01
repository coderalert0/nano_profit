class MarginAlertsController < ApplicationController
  def acknowledge
    @alert = Current.organization.margin_alerts.find(params[:id])
    @alert.acknowledge!(user: Current.user, notes: params[:notes])
    clear_alert_count_cache

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to alerts_path, notice: t("admin.margin_alerts.acknowledged") }
    end
  end

  def acknowledge_all
    Current.organization.margin_alerts.unacknowledged
      .update_all(acknowledged_at: Time.current, acknowledged_by_id: Current.user.id)
    clear_alert_count_cache

    redirect_to alerts_path, notice: t("admin.margin_alerts.all_acknowledged")
  end

  private

  def clear_alert_count_cache
    Rails.cache.delete("org:#{Current.organization.id}:unacked_alerts")
  end
end
