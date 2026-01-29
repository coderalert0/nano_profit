class DashboardController < ApplicationController
  def show
    @organization = Current.organization
    @margin = MarginCalculator.organization_margin(@organization)
    @vendor_costs = MarginCalculator.vendor_cost_breakdown(@organization)
    @recent_events = @organization.usage_telemetry_events
      .processed
      .recent
      .includes(:customer)
      .limit(20)
    @revenue_over_time = @organization.usage_telemetry_events
      .processed
      .group_by_day(:occurred_at)
      .sum(:revenue_amount_in_cents)
      .transform_values { |v| v / 100.0 }
    @cost_over_time = @organization.usage_telemetry_events
      .processed
      .group_by_day(:occurred_at)
      .sum(:total_cost_in_cents)
      .transform_values { |v| v / 100.0 }
    @unacknowledged_alerts_count = @organization.margin_alerts.unacknowledged.count
  end
end
