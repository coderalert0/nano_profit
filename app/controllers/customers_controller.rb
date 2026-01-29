class CustomersController < ApplicationController
  def index
    @customer_margins = MarginCalculator.customer_margins(Current.organization)
      .sort_by { |cm| cm[:margin].margin_bps }
  end

  def show
    @customer = Current.organization.customers.find(params[:id])
    @period = parse_period(params[:period])
    @selected_period = params[:period] || "all"

    @margin = MarginCalculator.customer_margin(@customer, @period)

    events = @customer.usage_telemetry_events.processed
    events = events.where(occurred_at: @period) if @period

    @events = events.recent.includes(:cost_entries).limit(50)
    @vendor_costs = CostEntry
      .where(usage_telemetry_event: events)
      .group(:vendor_name)
      .sum(:amount_in_cents)
    @revenue_over_time = events
      .group_by_day(:occurred_at)
      .sum(:revenue_amount_in_cents)
      .transform_values { |v| v / 100.0 }
    @cost_over_time = events
      .group_by_day(:occurred_at)
      .sum(:total_cost_in_cents)
      .transform_values { |v| v / 100.0 }
  end

  def edit
    @customer = Current.organization.customers.find(params[:id])
  end

  def update
    @customer = Current.organization.customers.find(params[:id])

    if @customer.update(customer_params)
      redirect_to @customer, notice: t("controllers.customers.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def customer_params
    params.require(:customer).permit(:monthly_subscription_revenue_in_cents)
  end

  def parse_period(period_param)
    case period_param
    when "7d"  then 7.days.ago..Time.current
    when "30d" then 30.days.ago..Time.current
    when "90d" then 90.days.ago..Time.current
    else nil
    end
  end
end
