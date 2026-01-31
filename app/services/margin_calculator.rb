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

    effective_period = period || events_date_range(events)
    sub_revenue = prorate_subscription(customer.monthly_subscription_revenue_in_cents, effective_period)
    total_revenue = event_result.revenue_in_cents + sub_revenue
    total_margin = total_revenue - event_result.cost_in_cents

    MarginResult.new(
      revenue_in_cents: total_revenue,
      cost_in_cents: event_result.cost_in_cents,
      margin_in_cents: total_margin,
      margin_bps: total_revenue > 0 ? ((total_margin * 10_000) / total_revenue).round.to_i : 0,
      subscription_revenue_in_cents: sub_revenue,
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

    total_sub_revenue = organization.customers.sum(:monthly_subscription_revenue_in_cents)
    effective_period = period || events_date_range(organization.events.processed)
    sub_revenue = prorate_subscription(total_sub_revenue, effective_period)
    total_revenue = event_result.revenue_in_cents + sub_revenue
    total_margin = total_revenue - event_result.cost_in_cents

    MarginResult.new(
      revenue_in_cents: total_revenue,
      cost_in_cents: event_result.cost_in_cents,
      margin_in_cents: total_margin,
      margin_bps: total_revenue > 0 ? ((total_margin * 10_000) / total_revenue).round.to_i : 0,
      subscription_revenue_in_cents: sub_revenue,
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

    effective_period = period || events_date_range(events)

    seen_customer_ids = Set.new

    results = events
      .joins(:customer)
      .group("customers.id", "customers.name", "customers.external_id", "customers.monthly_subscription_revenue_in_cents")
      .pluck(
        "customers.id",
        "customers.name",
        "customers.external_id",
        "customers.monthly_subscription_revenue_in_cents",
        Arel.sql("COALESCE(SUM(revenue_amount_in_cents), 0)"),
        Arel.sql("COALESCE(SUM(total_cost_in_cents), 0)"),
        Arel.sql("COALESCE(SUM(margin_in_cents), 0)")
      ).map do |id, name, ext_id, monthly_sub, event_revenue, cost, _event_margin|
        seen_customer_ids.add(id)
        sub_revenue = prorate_subscription(monthly_sub, effective_period)
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
            margin_bps: total_revenue > 0 ? ((total_margin * 10_000) / total_revenue).round.to_i : 0,
            subscription_revenue_in_cents: sub_revenue,
            event_revenue_in_cents: event_revenue
          )
        }
      end

    # Append subscription-only customers (have subscription revenue but no events in result set)
    organization.customers
      .where.not(monthly_subscription_revenue_in_cents: 0)
      .where.not(id: seen_customer_ids.to_a)
      .find_each do |customer|
        sub_revenue = prorate_subscription(customer.monthly_subscription_revenue_in_cents, effective_period)
        results << {
          customer_id: customer.id,
          customer_name: customer.name,
          customer_external_id: customer.external_id,
          margin: MarginResult.new(
            revenue_in_cents: sub_revenue,
            cost_in_cents: 0,
            margin_in_cents: sub_revenue,
            margin_bps: sub_revenue > 0 ? 10_000 : 0,
            subscription_revenue_in_cents: sub_revenue,
            event_revenue_in_cents: 0
          )
        }
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

  def self.prorate_subscription(monthly_cents, period)
    return 0 if period.nil? || monthly_cents == 0

    period_start = period.begin.to_date
    period_end = period.end.to_date

    total = BigDecimal("0")
    cursor = period_start

    while cursor < period_end
      month_end = cursor.end_of_month + 1.day  # first day of next month
      slice_end = [ month_end, period_end ].min
      days_in_slice = (slice_end - cursor).to_i
      days_in_month = Time.days_in_month(cursor.month, cursor.year)

      total += monthly_cents.to_d * days_in_slice / days_in_month
      cursor = slice_end
    end

    total.round
  end

  def self.events_date_range(events_scope)
    range = events_scope.pick(Arel.sql("MIN(occurred_at)"), Arel.sql("MAX(occurred_at)"))
    return nil unless range&.first && range&.last
    # Add 1 day to make the range inclusive of the last day's events
    range.first.to_date..(range.last.to_date + 1.day)
  end

  private_class_method :calculate, :prorate_subscription, :events_date_range
end
