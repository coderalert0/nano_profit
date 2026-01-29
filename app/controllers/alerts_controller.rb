class AlertsController < ApplicationController
  PER_PAGE = 20

  def index
    @page = [ params[:page].to_i, 1 ].max
    alerts = Current.organization.margin_alerts.recent.includes(:customer)
    @total_count = alerts.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @alerts = alerts.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

    if request.headers["Turbo-Frame"] == "infinite-scroll-rows"
      render partial: "rows", locals: { alerts: @alerts, page: @page, total_pages: @total_pages }, layout: false
    end
  end

  def acknowledge
    alert = Current.organization.margin_alerts.find(params[:id])
    alert.acknowledge!
    redirect_to alerts_path, notice: "Alert acknowledged."
  end
end
