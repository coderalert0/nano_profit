require "test_helper"

class MarginCalculatorTest < ActiveSupport::TestCase
  test "organization_margin returns correct totals including invoice revenue" do
    org = organizations(:acme)
    result = MarginCalculator.organization_margin(org)

    # Event revenue: 1000 (processed_event) + 0 (subscription_customer_event) = 1000
    assert_equal 1000, result.event_revenue_in_cents
    assert_equal 800, result.cost_in_cents
    # Invoice revenue comes from fixtures (all-time = full amounts)
    assert result.subscription_revenue_in_cents >= 0
    assert result.revenue_in_cents >= 1000
  end

  test "customer_margin returns correct totals for customer without invoices" do
    customer = customers(:customer_one)
    result = MarginCalculator.customer_margin(customer)

    assert_equal 1000, result.revenue_in_cents
    assert_equal 500, result.cost_in_cents
    assert_equal 500, result.margin_in_cents
    assert_equal 0, result.subscription_revenue_in_cents
    assert_equal 1000, result.event_revenue_in_cents
  end

  test "customer_margin includes invoice revenue" do
    customer = customers(:customer_with_subscription)
    result = MarginCalculator.customer_margin(customer)

    # Event revenue: 0, Cost: 300, Invoice revenue comes from fixtures
    assert_equal 300, result.cost_in_cents
    assert_equal 0, result.event_revenue_in_cents
    # All-time: full invoice amounts from fixtures
    assert result.subscription_revenue_in_cents > 0
  end

  test "customer with invoices shows positive margin with period" do
    customer = customers(:customer_with_subscription)
    # Use a period that overlaps with the monthly_invoice fixture (Jan 2026)
    period = Time.new(2026, 1, 1)..Time.new(2026, 1, 31)
    result = MarginCalculator.customer_margin(customer, period)

    assert result.subscription_revenue_in_cents > 0
    assert result.margin_in_cents > 0, "Invoice revenue should cover costs"
  end

  test "margin_bps is zero when revenue is zero" do
    org = Organization.create!(name: "Empty Org")
    result = MarginCalculator.organization_margin(org)

    assert_equal 0, result.revenue_in_cents
    assert_equal 0, result.margin_bps
  end

  test "vendor_cost_breakdown groups by vendor" do
    org = organizations(:acme)
    breakdown = MarginCalculator.vendor_cost_breakdown(org)

    assert breakdown["openai"].present?
  end

  test "organization_margin with time period filter prorates invoices" do
    org = organizations(:acme)
    # Use a 7-day period in January overlapping with the monthly_invoice fixture
    period_start = Time.new(2026, 1, 1)
    period_end = Time.new(2026, 1, 8)
    result = MarginCalculator.organization_margin(org, period_start..period_end)

    # monthly_invoice: 5000 cents for Jan 1-Feb 1 (31 days), overlap = 7 days
    # prorated: 5000 * 7 / 31 = 1129 (rounded)
    expected_inv = (5000.to_d * 7 / 31).round
    assert_equal expected_inv, result.subscription_revenue_in_cents
    # Events won't be in this range (fixtures use 1.hour.ago)
    assert_equal 0, result.event_revenue_in_cents
  end

  test "customer_margins returns per-customer breakdown" do
    org = organizations(:acme)
    margins = MarginCalculator.customer_margins(org)

    assert margins.length >= 2

    customer_one_margin = margins.find { |cm| cm[:customer_name] == "Customer One" }
    assert_not_nil customer_one_margin
    assert_equal 1000, customer_one_margin[:margin].event_revenue_in_cents

    sub_customer_margin = margins.find { |cm| cm[:customer_name] == "Subscription Customer" }
    assert_not_nil sub_customer_margin
    assert_equal 0, sub_customer_margin[:margin].event_revenue_in_cents
    assert_equal 300, sub_customer_margin[:margin].cost_in_cents
  end

  test "event_type_margins returns grouped results" do
    org = organizations(:acme)
    margins = MarginCalculator.event_type_margins(org)

    assert_equal 1, margins.length
    ai_analysis = margins.find { |etm| etm[:event_type] == "ai_analysis" }
    assert_not_nil ai_analysis
    assert_equal 2, ai_analysis[:event_count]
    assert_equal 1000, ai_analysis[:margin].revenue_in_cents
    assert_equal 800, ai_analysis[:margin].cost_in_cents
    assert_equal 200, ai_analysis[:margin].margin_in_cents
    assert_equal 0, ai_analysis[:margin].subscription_revenue_in_cents
  end

  test "no floating point in margin results" do
    org = organizations(:acme)
    result = MarginCalculator.organization_margin(org)

    assert_kind_of Numeric, result.margin_bps
    assert_kind_of Numeric, result.revenue_in_cents
    assert_kind_of Numeric, result.cost_in_cents
    assert_kind_of Numeric, result.margin_in_cents
    assert_kind_of Numeric, result.subscription_revenue_in_cents
    assert_kind_of Numeric, result.event_revenue_in_cents
    [ result.revenue_in_cents, result.cost_in_cents, result.margin_in_cents ].each do |val|
      assert_not_kind_of Float, val, "Expected BigDecimal or Integer, not Float"
    end
  end

  test "7-day period correctly prorates a monthly invoice" do
    customer = customers(:customer_with_subscription)

    # Use January (31 days) - 7-day period overlapping with monthly_invoice fixture
    period_start = Time.new(2026, 1, 1)
    period_end = Time.new(2026, 1, 8)
    result = MarginCalculator.customer_margin(customer, period_start..period_end)

    # monthly_invoice: 5000 * 7 / 31 = 1129 (rounded)
    expected = (5000.to_d * 7 / 31).round
    assert_equal expected, result.subscription_revenue_in_cents
  end

  test "no invoices returns zero invoice revenue" do
    customer = customers(:customer_one)
    period = Time.new(2026, 1, 1)..Time.new(2026, 1, 8)
    result = MarginCalculator.customer_margin(customer, period)

    assert_equal 0, result.subscription_revenue_in_cents
  end

  test "all-time sums full invoice amounts without proration" do
    customer = customers(:customer_with_subscription)
    result = MarginCalculator.customer_margin(customer)

    # All-time: sum of all invoice amounts (no proration)
    total_invoice_cents = customer.stripe_invoices.sum(:amount_in_cents)
    assert_equal total_invoice_cents, result.subscription_revenue_in_cents
  end

  test "customer_margins includes invoice-only customers without events in period" do
    org = organizations(:acme)

    # Use a period that includes the monthly_invoice fixture but excludes fixture events
    period = Time.new(2026, 1, 1)..Time.new(2026, 1, 8)
    margins = MarginCalculator.customer_margins(org, period)

    # customer_with_subscription has invoice revenue but no events in this period
    sub_customer = margins.find { |cm| cm[:customer_name] == "Subscription Customer" }
    assert_not_nil sub_customer, "Invoice-only customer should appear in results"
    assert sub_customer[:margin].subscription_revenue_in_cents > 0
    assert_equal 0, sub_customer[:margin].event_revenue_in_cents
    assert_equal 0, sub_customer[:margin].cost_in_cents
  end

  test "same-day invoice returns full amount" do
    customer = customers(:customer_with_subscription)
    org = customer.organization

    # Create a same-day invoice (period_start == period_end on same date)
    same_day = org.stripe_invoices.create!(
      stripe_invoice_id: "inv_same_day",
      stripe_customer_id: "cus_sub_001",
      customer: customer,
      amount_in_cents: 3000,
      period_start: Time.new(2026, 1, 15),
      period_end: Time.new(2026, 1, 15),
      paid_at: Time.new(2026, 1, 15)
    )

    period = Time.new(2026, 1, 14)..Time.new(2026, 1, 16)
    result = MarginCalculator.customer_margin(customer, period)

    # Same-day invoice should return full amount, not 0
    assert result.subscription_revenue_in_cents >= 3000,
      "Same-day invoice should contribute its full amount (#{same_day.amount_in_cents}), got #{result.subscription_revenue_in_cents}"
  ensure
    same_day&.destroy
  end

  test "invoice proration arithmetic - no floating point" do
    customer = customers(:customer_with_subscription)

    period_start = Time.new(2026, 1, 1)
    period_end = Time.new(2026, 1, 8)
    result = MarginCalculator.customer_margin(customer, period_start..period_end)

    assert_kind_of Numeric, result.subscription_revenue_in_cents
    assert_not_kind_of Float, result.subscription_revenue_in_cents
  end
end
