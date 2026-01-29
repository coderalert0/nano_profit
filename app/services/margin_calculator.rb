class MarginCalculator
  MarginResult = Struct.new(:revenue_in_cents, :cost_in_cents, :margin_in_cents, :margin_bps, keyword_init: true)

  def self.customer_margin(customer, period = nil)
    events = customer.usage_telemetry_events.processed
    events = events.where(occurred_at: period) if period
    calculate(events)
  end

  def self.event_type_margin(organization, event_type, period = nil)
    events = organization.usage_telemetry_events.processed.where(event_type: event_type)
    events = events.where(occurred_at: period) if period
    calculate(events)
  end

  def self.organization_margin(organization, period = nil)
    events = organization.usage_telemetry_events.processed
    events = events.where(occurred_at: period) if period
    calculate(events)
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
      .group("customers.id", "customers.name", "customers.external_id")
      .pluck(
        "customers.id",
        "customers.name",
        "customers.external_id",
        "SUM(revenue_amount_in_cents)",
        "SUM(total_cost_in_cents)",
        "SUM(margin_in_cents)"
      ).map do |id, name, ext_id, revenue, cost, margin|
        {
          customer_id: id,
          customer_name: name,
          customer_external_id: ext_id,
          margin: MarginResult.new(
            revenue_in_cents: revenue,
            cost_in_cents: cost,
            margin_in_cents: margin,
            margin_bps: revenue > 0 ? (margin * 10_000) / revenue : 0
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
      margin_bps: revenue > 0 ? (margin * 10_000) / revenue : 0
    )
  end

  private_class_method :calculate
end
