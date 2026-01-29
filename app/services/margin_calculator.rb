class MarginCalculator
  MarginResult = Struct.new(
    :revenue_in_cents, :cost_in_cents, :margin_in_cents, :margin_bps,
    :subscription_revenue_in_cents, :event_revenue_in_cents,
    keyword_init: true
  )

  def self.customer_margin(customer, period = nil)
    events = customer.usage_telemetry_events.processed
    events = events.where(occurred_at: period) if period
    event_result = calculate(events)

    sub_revenue = prorate_subscription(customer.monthly_subscription_revenue_in_cents, period)
    total_revenue = event_result.revenue_in_cents + sub_revenue
    total_margin = total_revenue - event_result.cost_in_cents

    MarginResult.new(
      revenue_in_cents: total_revenue,
      cost_in_cents: event_result.cost_in_cents,
      margin_in_cents: total_margin,
      margin_bps: total_revenue > 0 ? (total_margin * 10_000) / total_revenue : 0,
      subscription_revenue_in_cents: sub_revenue,
      event_revenue_in_cents: event_result.revenue_in_cents
    )
  end

  def self.event_type_margin(organization, event_type, period = nil)
    events = organization.usage_telemetry_events.processed.where(event_type: event_type)
    events = events.where(occurred_at: period) if period
    calculate(events)
  end

  def self.organization_margin(organization, period = nil)
    events = organization.usage_telemetry_events.processed
    events = events.where(occurred_at: period) if period
    event_result = calculate(events)

    total_sub_revenue = organization.customers.sum(:monthly_subscription_revenue_in_cents)
    sub_revenue = prorate_subscription(total_sub_revenue, period)
    total_revenue = event_result.revenue_in_cents + sub_revenue
    total_margin = total_revenue - event_result.cost_in_cents

    MarginResult.new(
      revenue_in_cents: total_revenue,
      cost_in_cents: event_result.cost_in_cents,
      margin_in_cents: total_margin,
      margin_bps: total_revenue > 0 ? (total_margin * 10_000) / total_revenue : 0,
      subscription_revenue_in_cents: sub_revenue,
      event_revenue_in_cents: event_result.revenue_in_cents
    )
  end

  def self.vendor_cost_breakdown(organization, period = nil)
    events = organization.usage_telemetry_events.processed
    events = events.where(occurred_at: period) if period

    CostEntry.where(usage_telemetry_event_id: events.select(:id))
      .group(:vendor_name)
      .sum(:amount_in_cents)
  end

  def self.customer_margins(organization, period = nil)
    events = organization.usage_telemetry_events.processed
    events = events.where(occurred_at: period) if period

    events
      .joins(:customer)
      .group("customers.id", "customers.name", "customers.external_id", "customers.monthly_subscription_revenue_in_cents")
      .pluck(
        "customers.id",
        "customers.name",
        "customers.external_id",
        "customers.monthly_subscription_revenue_in_cents",
        "SUM(revenue_amount_in_cents)",
        "SUM(total_cost_in_cents)",
        "SUM(margin_in_cents)"
      ).map do |id, name, ext_id, monthly_sub, event_revenue, cost, _event_margin|
        sub_revenue = prorate_subscription(monthly_sub, period)
        total_revenue = event_revenue + sub_revenue
        total_margin = total_revenue - cost

        {
          customer_id: id,
          customer_name: name,
          customer_external_id: ext_id,
          margin: MarginResult.new(
            revenue_in_cents: total_revenue,
            cost_in_cents: cost,
            margin_in_cents: total_margin,
            margin_bps: total_revenue > 0 ? (total_margin * 10_000) / total_revenue : 0,
            subscription_revenue_in_cents: sub_revenue,
            event_revenue_in_cents: event_revenue
          )
        }
      end
  end

  def self.calculate(events)
    totals = events.pick(
      Arel.sql("COALESCE(SUM(revenue_amount_in_cents), 0)"),
      Arel.sql("COALESCE(SUM(total_cost_in_cents), 0)"),
      Arel.sql("COALESCE(SUM(margin_in_cents), 0)")
    )
    revenue, cost, margin = totals.map(&:to_i)

    MarginResult.new(
      revenue_in_cents: revenue,
      cost_in_cents: cost,
      margin_in_cents: margin,
      margin_bps: revenue > 0 ? (margin * 10_000) / revenue : 0,
      subscription_revenue_in_cents: 0,
      event_revenue_in_cents: revenue
    )
  end

  def self.prorate_subscription(monthly_cents, period)
    return monthly_cents if period.nil?
    return 0 if monthly_cents == 0

    period_start = period.begin.to_date
    period_end = period.end.to_date
    days_in_period = (period_end - period_start).to_i
    days_in_month = Time.days_in_month(period_start.month, period_start.year)

    (monthly_cents * days_in_period) / days_in_month
  end

  private_class_method :calculate, :prorate_subscription
end
