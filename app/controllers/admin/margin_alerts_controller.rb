module Admin
  class MarginAlertsController < BaseController
    def acknowledge
      @alert = MarginAlert.find(params[:id])
      @alert.acknowledge!(user: Current.user, notes: params[:notes])

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to alerts_path, notice: t("admin.margin_alerts.acknowledged") }
      end
    end

    def acknowledge_all
      MarginAlert.unacknowledged.find_each do |alert|
        alert.acknowledge!(user: Current.user)
      end

      redirect_to alerts_path, notice: t("admin.margin_alerts.all_acknowledged")
    end
  end
end
