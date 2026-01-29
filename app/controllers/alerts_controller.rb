class AlertsController < ApplicationController
  PER_PAGE = 20

  def index
    @page = [ params[:page].to_i, 1 ].max
    @status_filter = params[:status].presence
    @type_filter = params[:type].presence

    alerts = Current.organization.margin_alerts.recent.includes(:customer)
    alerts = alerts.unacknowledged if @status_filter == "active"
    alerts = alerts.where.not(acknowledged_at: nil) if @status_filter == "acknowledged"
    alerts = alerts.where(alert_type: @type_filter) if @type_filter.present?
    @total_count = alerts.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @alerts = alerts.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

    if request.headers["Turbo-Frame"] == "infinite-scroll-rows"
      render partial: "rows", locals: { alerts: @alerts, page: @page, total_pages: @total_pages }, layout: false
    end
  end

end
