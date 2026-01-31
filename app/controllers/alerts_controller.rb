class AlertsController < ApplicationController
  PER_PAGE = 20

  def index
    @page = [ params[:page].to_i, 1 ].max
    @status_filter = params[:status].presence
    @type_filter = params[:type].presence
    @dimension_filter = params[:dimension].presence

    alerts = Current.organization.margin_alerts.recent
    alerts = alerts.unacknowledged if @status_filter == "active"
    alerts = alerts.where.not(acknowledged_at: nil) if @status_filter == "acknowledged"
    alerts = alerts.where(alert_type: @type_filter) if @type_filter.present?
    alerts = alerts.where(dimension: @dimension_filter) if @dimension_filter.present?
    @total_count = alerts.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @alerts = alerts.includes(:organization, :acknowledged_by).offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

    # Batch-load customers referenced by customer alerts to avoid N+1
    customer_alerts = @alerts.select(&:customer?)
    if customer_alerts.any?
      customer_ids = customer_alerts.map(&:dimension_value)
      @alert_customers = Current.organization.customers.where(id: customer_ids).index_by { |c| c.id.to_s }
    else
      @alert_customers = {}
    end

    if request.headers["Turbo-Frame"] == "infinite-scroll-rows"
      render partial: "rows", locals: { alerts: @alerts, page: @page, total_pages: @total_pages, alert_customers: @alert_customers }, layout: false
    end
  end

end
