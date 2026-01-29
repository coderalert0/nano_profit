class CustomersController < ApplicationController
  def index
    @customer_margins = MarginCalculator.customer_margins(Current.organization)
      .sort_by { |cm| cm[:margin].margin_bps }
  end

  def show
    @customer = Current.organization.customers.find(params[:id])
    @margin = MarginCalculator.customer_margin(@customer)
    @events = @customer.usage_telemetry_events
      .processed
      .recent
      .includes(:cost_entries)
      .limit(50)
    @vendor_costs = CostEntry
      .where(usage_telemetry_event: @customer.usage_telemetry_events.processed)
      .group(:vendor_name)
      .sum(:amount_in_cents)
    @revenue_over_time = @customer.usage_telemetry_events
      .processed
      .group_by_day(:occurred_at)
      .sum(:revenue_amount_in_cents)
      .transform_values { |v| v / 100.0 }
    @cost_over_time = @customer.usage_telemetry_events
      .processed
      .group_by_day(:occurred_at)
      .sum(:total_cost_in_cents)
      .transform_values { |v| v / 100.0 }
  end
end
