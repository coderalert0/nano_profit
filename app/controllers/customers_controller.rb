class CustomersController < ApplicationController
  PER_PAGE = 20

  def index
    @page = [ params[:page].to_i, 1 ].max
    resolve_period
    all_margins = MarginCalculator.customer_margins(Current.organization, @period)
      .sort_by { |cm| cm[:margin].margin_bps }
    @total_count = all_margins.size
    @total_pages = (@total_count.to_f / PER_PAGE).ceil
    @customer_margins = all_margins.slice((@page - 1) * PER_PAGE, PER_PAGE) || []

    if request.headers["Turbo-Frame"] == "infinite-scroll-rows"
      render partial: "rows", locals: { customer_margins: @customer_margins, page: @page, total_pages: @total_pages }, layout: false
    end
  end

  def show
    @customer = Current.organization.customers.find(params[:id])
    resolve_period

    @margin = MarginCalculator.customer_margin(@customer, @period)

    customer_events = @customer.events.processed.includes(:cost_entries)
    customer_events = customer_events.where(occurred_at: @period) if @period
    @event_type_margins = customer_events
      .group(:event_type)
      .pluck(
        :event_type,
        Arel.sql("COALESCE(SUM(revenue_amount_in_cents), 0)"),
        Arel.sql("COALESCE(SUM(total_cost_in_cents), 0)"),
        Arel.sql("COALESCE(SUM(margin_in_cents), 0)")
      )
      .map { |et, rev, _cost, margin| [ et, rev > 0 ? ((margin * 10_000) / rev).to_i / 100.0 : 0.0 ] }
      .sort_by { |_, bps| bps }
      .first(10)
      .to_h
    @event_type_urls = @event_type_margins.keys
      .to_h { |et| [ et, Rails.application.routes.url_helpers.events_path(event_type: [ et ], customer_id: [ @customer.id ]) ] }

    @vendor_costs = CostEntry
      .where(event: @customer.events.processed.then { |e| @period ? e.where(occurred_at: @period) : e })
      .group(:vendor_name)
      .sum(:amount_in_cents)
    @revenue_over_time = (@period ? @customer.events.processed.where(occurred_at: @period) : @customer.events.processed)
      .group_by_day(:occurred_at)
      .sum(:revenue_amount_in_cents)
      .transform_values { |v| v / 100.0 }
    @cost_over_time = (@period ? @customer.events.processed.where(occurred_at: @period) : @customer.events.processed)
      .group_by_day(:occurred_at)
      .sum(:total_cost_in_cents)
      .transform_values { |v| v / 100.0 }
  end
end
