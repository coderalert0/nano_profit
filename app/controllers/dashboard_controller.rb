class DashboardController < ApplicationController
  def show
    @organization = Current.organization
    resolve_period

    cache_key = "dashboard:#{@organization.id}:#{@selected_period}"

    cached = Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      margin = MarginCalculator.organization_margin(@organization, @period)
      model_costs = MarginCalculator.model_cost_breakdown(@organization, @period)
        .sort_by { |_, v| -v }
        .first(10)
        .to_h

      event_type_data = MarginCalculator.event_type_margins(@organization, @period)
        .sort_by { |et| et[:margin].margin_bps }
        .first(10)

      customer_data = MarginCalculator.customer_margins(@organization, @period)
        .sort_by { |c| c[:margin].margin_bps }
        .first(10)

      events = @organization.events.processed
      events = events.where(occurred_at: @period) if @period
      revenue_over_time = events
        .group_by_day(:occurred_at)
        .sum(:revenue_amount_in_cents)
        .transform_values { |v| v / 100.0 }
      cost_over_time = events
        .group_by_day(:occurred_at)
        .sum(:total_cost_in_cents)
        .transform_values { |v| v / 100.0 }

      {
        margin: margin,
        model_costs: model_costs,
        event_type_data: event_type_data,
        customer_data: customer_data,
        revenue_over_time: revenue_over_time,
        cost_over_time: cost_over_time
      }
    end

    @margin = cached[:margin]
    @model_costs = cached[:model_costs]

    event_type_data = cached[:event_type_data]
    @event_type_margins = event_type_data
      .map { |et| [ et[:event_type], (et[:margin].margin_bps / 100.0).round(1) ] }
      .to_h
    @event_type_urls = event_type_data
      .to_h { |et| [ et[:event_type], Rails.application.routes.url_helpers.events_path(event_type: [ et[:event_type] ]) ] }

    customer_data = cached[:customer_data]
    @customer_margins = customer_data
      .map { |c| [ c[:customer_name] || c[:customer_external_id], (c[:margin].margin_bps / 100.0).round(1) ] }
      .to_h
    @customer_urls = customer_data
      .to_h { |c| [ c[:customer_name] || c[:customer_external_id], Rails.application.routes.url_helpers.customer_path(c[:customer_id]) ] }

    @revenue_over_time = cached[:revenue_over_time]
    @cost_over_time = cached[:cost_over_time]
  end
end
