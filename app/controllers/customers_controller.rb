class CustomersController < ApplicationController
  PER_PAGE = 20

  def index
    @page = [ params[:page].to_i, 1 ].max
    @period = parse_period(params[:period])
    @selected_period = params[:period] || "all"
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
    @page = [ params[:page].to_i, 1 ].max
    @period = parse_period(params[:period])
    @selected_period = params[:period] || "all"

    @margin = MarginCalculator.customer_margin(@customer, @period)

    events = @customer.events.processed
    events = events.where(occurred_at: @period) if @period

    @total_event_count = events.count
    @total_event_pages = (@total_event_count.to_f / PER_PAGE).ceil
    @events = events.recent.includes(:cost_entries)
      .offset((@page - 1) * PER_PAGE)
      .limit(PER_PAGE)

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

    if request.headers["Turbo-Frame"] == "infinite-scroll-rows"
      render partial: "event_rows", locals: { events: @events, page: @page, total_pages: @total_event_pages }, layout: false
    end
  end

  private

  def parse_period(period_param)
    case period_param
    when "7d"  then 7.days.ago..Time.current
    when "30d" then 30.days.ago..Time.current
    when "90d" then 90.days.ago..Time.current
    else nil
    end
  end
end
