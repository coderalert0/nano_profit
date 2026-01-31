class EventsController < ApplicationController
  PER_PAGE = 20

  def index
    @page = [ params[:page].to_i, 1 ].max
    resolve_period

    events = Current.organization.events.processed
    events = events.where(occurred_at: @period) if @period

    @selected_event_types = Array(params[:event_type]).reject(&:blank?)
    @selected_customer_ids = Array(params[:customer_id]).reject(&:blank?)
    @selected_vendors = Array(params[:vendor]).reject(&:blank?)

    events = events.where(event_type: @selected_event_types) if @selected_event_types.any?
    events = events.where(customer_id: @selected_customer_ids) if @selected_customer_ids.any?
    if @selected_vendors.any?
      events = events.joins(:cost_entries).where(cost_entries: { vendor_name: @selected_vendors }).distinct
    end

    @event_types = Current.organization.events.processed
      .distinct.pluck(:event_type).sort
    @customers = Current.organization.customers.order(:name)
    @vendors = CostEntry.where(event_id: Current.organization.events.processed.select(:id))
      .distinct.pluck(:vendor_name).sort

    @total_count = events.count
    @total_pages = (@total_count.to_f / PER_PAGE).ceil

    @events = events
      .recent
      .includes(:customer, :cost_entries)
      .offset((@page - 1) * PER_PAGE)
      .limit(PER_PAGE)

    if request.headers["Turbo-Frame"] == "infinite-scroll-rows"
      render partial: "rows", locals: { events: @events, page: @page, total_pages: @total_pages }, layout: false
    end
  end
end
