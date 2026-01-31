class DashboardController < ApplicationController
  def show
    @organization = Current.organization
    @period = parse_period(params[:period])
    @selected_period = params[:period] || "all"

    @margin = MarginCalculator.organization_margin(@organization, @period)
    @model_costs = MarginCalculator.model_cost_breakdown(@organization, @period)
      .sort_by { |_, v| -v }
      .first(10)
      .to_h

    @event_type_margins = MarginCalculator.event_type_margins(@organization, @period)
      .sort_by { |et| et[:margin].margin_bps }
      .first(10)
      .map { |et| [ et[:event_type], (et[:margin].margin_bps / 100.0).round(1) ] }
      .to_h

    @customer_margins = MarginCalculator.customer_margins(@organization, @period)
      .sort_by { |c| c[:margin].margin_bps }
      .first(10)
      .map { |c| [ c[:customer_name] || c[:customer_external_id], (c[:margin].margin_bps / 100.0).round(1) ] }
      .to_h

    events = @organization.events.processed
    events = events.where(occurred_at: @period) if @period
    @revenue_over_time = events
      .group_by_day(:occurred_at)
      .sum(:revenue_amount_in_cents)
      .transform_values { |v| v / 100.0 }
    @cost_over_time = events
      .group_by_day(:occurred_at)
      .sum(:total_cost_in_cents)
      .transform_values { |v| v / 100.0 }
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
