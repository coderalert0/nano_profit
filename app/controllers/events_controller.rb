class EventsController < ApplicationController
  PER_PAGE = 50

  def index
    @page = [params[:page].to_i, 1].max

    events = Current.organization.usage_telemetry_events.processed

    if params[:event_type].present?
      events = events.where(event_type: params[:event_type])
    end

    if params[:customer_id].present?
      events = events.where(customer_id: params[:customer_id])
    end

    @event_types = Current.organization.usage_telemetry_events.processed
      .distinct.pluck(:event_type).sort
    @customers = Current.organization.customers.order(:name)

    @selected_event_type = params[:event_type]
    @selected_customer_id = params[:customer_id]

    @events = events
      .recent
      .includes(:customer, :cost_entries)
      .offset((@page - 1) * PER_PAGE)
      .limit(PER_PAGE + 1)

    @has_next_page = @events.size > PER_PAGE
    @events = @events.first(PER_PAGE)
  end
end
