class DashboardController < ApplicationController
  def show
    @organization = Current.organization
    @period = parse_period(params[:period])
    @selected_period = params[:period] || "all"

    @margin = MarginCalculator.organization_margin(@organization, @period)
    @vendor_costs = MarginCalculator.vendor_cost_breakdown(@organization, @period)
    @recent_events = @organization.usage_telemetry_events
      .processed
      .recent
      .includes(:customer)
      .limit(20)

    events = @organization.usage_telemetry_events.processed
    events = events.where(occurred_at: @period) if @period
    @revenue_over_time = events
      .group_by_day(:occurred_at)
      .sum(:revenue_amount_in_cents)
      .transform_values { |v| v / 100.0 }
    @cost_over_time = events
      .group_by_day(:occurred_at)
      .sum(:total_cost_in_cents)
      .transform_values { |v| v / 100.0 }
    @unacknowledged_alerts_count = @organization.margin_alerts.unacknowledged.count
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
