module Admin
  class MarginAlertsController < BaseController
    def acknowledge
      @alert = Current.organization.margin_alerts.find(params[:id])
      @alert.acknowledge!(user: Current.user, notes: params[:notes])

      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to alerts_path, notice: "Alert acknowledged." }
      end
    end
  end
end
