class MarginCalculator
  MarginResult = Struct.new(
    :revenue_in_cents, :cost_in_cents, :margin_in_cents, :margin_bps,
    :subscription_revenue_in_cents, :event_revenue_in_cents,
    keyword_init: true
  )

  def self.customer_margin(customer, period = nil)
    events = customer.events.processed
    events = events.where(occurred_at: period) if period
    event_result = calculate(events)

    inv_revenue = invoice_revenue_for_period(customer.stripe_invoices, period)
    total_revenue = event_result.revenue_in_cents + inv_revenue
    total_margin = total_revenue - event_result.cost_in_cents

    MarginResult.new(
      revenue_in_cents: total_revenue,
      cost_in_cents: event_result.cost_in_cents,
      margin_in_cents: total_margin,
      margin_bps: total_revenue > 0 ? ((total_margin * 10_000) / total_revenue).round.to_i : 0,
      subscription_revenue_in_cents: inv_revenue,
      event_revenue_in_cents: event_result.revenue_in_cents
    )
  end

  def self.event_type_margins(organization, period = nil)
    events = organization.events.processed
    events = events.where(occurred_at: period) if period

    events
      .group(:event_type)
      .pluck(
        :event_type,
        Arel.sql("COALESCE(SUM(revenue_amount_in_cents), 0)"),
        Arel.sql("COALESCE(SUM(total_cost_in_cents), 0)"),
        Arel.sql("COALESCE(SUM(margin_in_cents), 0)"),
        Arel.sql("COUNT(*)")
      ).map do |event_type, revenue, cost, margin, count|
        {
          event_type: event_type,
          event_count: count,
          margin: MarginResult.new(
            revenue_in_cents: revenue,
            cost_in_cents: cost,
            margin_in_cents: margin,
            margin_bps: revenue > 0 ? ((margin * 10_000) / revenue).round.to_i : 0,
            subscription_revenue_in_cents: 0,
            event_revenue_in_cents: revenue
          )
        }
      end
  end

  def self.event_type_margin(organization, event_type, period = nil)
    events = organization.events.processed.where(event_type: event_type)
    events = events.where(occurred_at: period) if period
    calculate(events)
  end

  def self.organization_margin(organization, period = nil)
    events = organization.events.processed
    events = events.where(occurred_at: period) if period
    event_result = calculate(events)

    inv_revenue = invoice_revenue_for_period(organization.stripe_invoices, period)
    total_revenue = event_result.revenue_in_cents + inv_revenue
    total_margin = total_revenue - event_result.cost_in_cents

    MarginResult.new(
      revenue_in_cents: total_revenue,
      cost_in_cents: event_result.cost_in_cents,
      margin_in_cents: total_margin,
      margin_bps: total_revenue > 0 ? ((total_margin * 10_000) / total_revenue).round.to_i : 0,
      subscription_revenue_in_cents: inv_revenue,
      event_revenue_in_cents: event_result.revenue_in_cents
    )
  end

  def self.vendor_cost_breakdown(organization, period = nil)
    events = organization.events.processed
    events = events.where(occurred_at: period) if period

    CostEntry.where(event_id: events.select(:id))
      .group(:vendor_name)
      .sum(:amount_in_cents)
  end

  def self.customer_margins(organization, period = nil)
    events = organization.events.processed
    events = events.where(occurred_at: period) if period

    seen_customer_ids = Set.new

    results = events
      .joins(:customer)
      .group("customers.id", "customers.name", "customers.external_id")
      .pluck(
        "customers.id",
        "customers.name",
        "customers.external_id",
        Arel.sql("COALESCE(SUM(revenue_amount_in_cents), 0)"),
        Arel.sql("COALESCE(SUM(total_cost_in_cents), 0)"),
        Arel.sql("COALESCE(SUM(margin_in_cents), 0)")
      ).map do |id, name, ext_id, event_revenue, cost, _event_margin|
        seen_customer_ids.add(id)
        inv_revenue = invoice_revenue_for_period(
          organization.stripe_invoices.where(customer_id: id), period
        )
        total_revenue = event_revenue + inv_revenue
        total_margin = total_revenue - cost

        {
          customer_id: id,
          customer_name: name,
          customer_external_id: ext_id,
          margin: MarginResult.new(
            revenue_in_cents: total_revenue,
            cost_in_cents: cost,
            margin_in_cents: total_margin,
            margin_bps: total_revenue > 0 ? ((total_margin * 10_000) / total_revenue).round.to_i : 0,
            subscription_revenue_in_cents: inv_revenue,
            event_revenue_in_cents: event_revenue
          )
        }
      end

    # Append invoice-only customers (have invoices but no events in result set)
    invoice_only_customer_ids = organization.stripe_invoices
      .where.not(customer_id: nil)
      .where.not(customer_id: seen_customer_ids.to_a)
      .distinct.pluck(:customer_id)

    if invoice_only_customer_ids.any?
      organization.customers.where(id: invoice_only_customer_ids).find_each do |customer|
        inv_revenue = invoice_revenue_for_period(customer.stripe_invoices, period)
        next if inv_revenue == 0

        results << {
          customer_id: customer.id,
          customer_name: customer.name,
          customer_external_id: customer.external_id,
          margin: MarginResult.new(
            revenue_in_cents: inv_revenue,
            cost_in_cents: 0,
            margin_in_cents: inv_revenue,
            margin_bps: inv_revenue > 0 ? 10_000 : 0,
            subscription_revenue_in_cents: inv_revenue,
            event_revenue_in_cents: 0
          )
        }
      end
    end

    results
  end

  def self.model_cost_breakdown(organization, period = nil)
    events = organization.events.processed
    events = events.where(occurred_at: period) if period

    CostEntry.where(event_id: events.select(:id))
      .group(:vendor_name, Arel.sql("metadata->>'ai_model_name'"))
      .sum(:amount_in_cents)
      .reject { |(vendor, model), _| vendor.blank? || model.blank? }
      .transform_keys { |vendor, model| "#{vendor}/#{model}" }
  end

  def self.calculate(events)
    totals = events.pick(
      Arel.sql("COALESCE(SUM(revenue_amount_in_cents), 0)"),
      Arel.sql("COALESCE(SUM(total_cost_in_cents), 0)"),
      Arel.sql("COALESCE(SUM(margin_in_cents), 0)")
    )
    revenue, cost, margin = totals.map(&:to_d)

    MarginResult.new(
      revenue_in_cents: revenue,
      cost_in_cents: cost,
      margin_in_cents: margin,
      margin_bps: revenue > 0 ? ((margin * 10_000) / revenue).round.to_i : 0,
      subscription_revenue_in_cents: 0,
      event_revenue_in_cents: revenue
    )
  end

  def self.invoice_revenue_for_period(invoices_scope, period)
    return invoices_scope.sum(:amount_in_cents) if period.nil?

    period_start = period.begin
    period_end = period.end

    overlapping = invoices_scope.where(
      "period_start < ? AND period_end > ?", period_end, period_start
    )

    overlapping.sum do |inv|
      overlap_start = [ inv.period_start, period_start ].max
      overlap_end = [ inv.period_end, period_end ].min
      overlap_days = (overlap_end.to_date - overlap_start.to_date).to_i
      invoice_days = (inv.period_end.to_date - inv.period_start.to_date).to_i
      next 0 if invoice_days <= 0
      (inv.amount_in_cents.to_d * overlap_days / invoice_days).round
    end
  end

  def self.events_date_range(events_scope)
    range = events_scope.pick(Arel.sql("MIN(occurred_at)"), Arel.sql("MAX(occurred_at)"))
    return nil unless range&.first && range&.last
    # Add 1 day to make the range inclusive of the last day's events
    range.first.to_date..(range.last.to_date + 1.day)
  end

  private_class_method :calculate, :invoice_revenue_for_period, :events_date_range
end
