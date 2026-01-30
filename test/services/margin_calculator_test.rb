require "test_helper"

class MarginCalculatorTest < ActiveSupport::TestCase
  test "organization_margin returns correct totals including prorated subscription revenue" do
    org = organizations(:acme)
    result = MarginCalculator.organization_margin(org)

    # Event revenue: 1000 (processed_event) + 0 (subscription_customer_event) = 1000
    # With minimum 1-day range, sub_revenue will be non-zero
    assert_equal 1000, result.event_revenue_in_cents
    assert_equal 800, result.cost_in_cents
    assert result.subscription_revenue_in_cents >= 0
    assert result.revenue_in_cents >= 1000
  end

  test "customer_margin returns correct totals for customer without subscription" do
    customer = customers(:customer_one)
    result = MarginCalculator.customer_margin(customer)

    assert_equal 1000, result.revenue_in_cents
    assert_equal 500, result.cost_in_cents
    assert_equal 500, result.margin_in_cents
    assert_equal 0, result.subscription_revenue_in_cents
    assert_equal 1000, result.event_revenue_in_cents
  end

  test "customer_margin includes prorated subscription revenue" do
    customer = customers(:customer_with_subscription)
    result = MarginCalculator.customer_margin(customer)

    # Event revenue: 0, Subscription prorated over event date range, Cost: 300
    assert_equal 300, result.cost_in_cents
    assert_equal 0, result.event_revenue_in_cents
    # With minimum 1-day range, subscription revenue should be > 0
    assert result.subscription_revenue_in_cents > 0
  end

  test "subscription customer with zero event revenue shows positive margin with period" do
    customer = customers(:customer_with_subscription)
    period = 30.days.ago..Time.current
    result = MarginCalculator.customer_margin(customer, period)

    assert result.subscription_revenue_in_cents > 0
    assert result.margin_in_cents > 0, "Subscription revenue should cover costs"
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

    # All cost entries are openai in updated fixtures
    assert breakdown["openai"].present?
  end

  test "organization_margin with time period filter prorates subscription" do
    org = organizations(:acme)
    # Use a 7-day period in January to get deterministic proration
    period_start = Time.new(2026, 1, 1)
    period_end = Time.new(2026, 1, 8)
    result = MarginCalculator.organization_margin(org, period_start..period_end)

    # Subscription: 5000 total monthly * 7 / 31 = 1129
    assert_equal 1129, result.subscription_revenue_in_cents
    # Events won't be in this range (fixtures use 1.hour.ago), so event revenue = 0
    assert_equal 0, result.event_revenue_in_cents
  end

  test "customer_margins returns per-customer breakdown" do
    org = organizations(:acme)
    margins = MarginCalculator.customer_margins(org)

    assert_equal 2, margins.length

    customer_one_margin = margins.find { |cm| cm[:customer_name] == "Customer One" }
    assert_not_nil customer_one_margin
    assert_equal 1000, customer_one_margin[:margin].event_revenue_in_cents

    sub_customer_margin = margins.find { |cm| cm[:customer_name] == "Subscription Customer" }
    assert_not_nil sub_customer_margin
    assert_equal 0, sub_customer_margin[:margin].event_revenue_in_cents
    assert_equal 300, sub_customer_margin[:margin].cost_in_cents
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

  test "proration uses actual days in month" do
    customer = customers(:customer_with_subscription)

    # Use January (31 days) - 7-day period
    period_start = Time.new(2026, 1, 1)
    period_end = Time.new(2026, 1, 8)
    result = MarginCalculator.customer_margin(customer, period_start..period_end)

    # 5000 * 7 / 31 = 1129 (integer division)
    assert_equal 1129, result.subscription_revenue_in_cents

    # Use February (28 days) - 7-day period
    period_start = Time.new(2026, 2, 1)
    period_end = Time.new(2026, 2, 8)
    result = MarginCalculator.customer_margin(customer, period_start..period_end)

    # 5000 * 7 / 28 = 1250
    assert_equal 1250, result.subscription_revenue_in_cents
  end

  test "proration arithmetic - no floating point" do
    customer = customers(:customer_with_subscription)

    period_start = Time.new(2026, 1, 1)
    period_end = Time.new(2026, 1, 8)
    result = MarginCalculator.customer_margin(customer, period_start..period_end)

    assert_kind_of Numeric, result.subscription_revenue_in_cents
    assert_not_kind_of Float, result.subscription_revenue_in_cents
  end

  test "multi-month proration iterates month by month" do
    customer = customers(:customer_with_subscription)

    # Jan 15 to Feb 15: 17 days in Jan (Jan 15..Feb 1) + 14 days in Feb (Feb 1..Feb 15)
    period_start = Time.new(2026, 1, 15)
    period_end = Time.new(2026, 2, 15)
    result = MarginCalculator.customer_margin(customer, period_start..period_end)

    # 5000 * 17/31 + 5000 * 14/28 = 2741.9... + 2500 = 5241.9... → 5242 rounded
    expected = (5000.to_d * 17 / 31 + 5000.to_d * 14 / 28).round
    assert_equal expected, result.subscription_revenue_in_cents
  end

  test "same-day events produce non-zero subscription revenue with minimum 1-day range" do
    customer = customers(:customer_with_subscription)

    # Create an event for the subscription customer at a specific time
    # The fixture already has subscription_customer_event at 1.hour.ago
    result = MarginCalculator.customer_margin(customer)

    # Should have at least 1 day of subscription revenue due to minimum range
    assert result.subscription_revenue_in_cents > 0
  end

  test "customer_margins includes subscription-only customers without events in period" do
    org = organizations(:acme)

    # Use a period that excludes fixture events
    period = Time.new(2026, 1, 1)..Time.new(2026, 1, 8)
    margins = MarginCalculator.customer_margins(org, period)

    # customer_with_subscription has subscription revenue but no events in this period
    sub_customer = margins.find { |cm| cm[:customer_name] == "Subscription Customer" }
    assert_not_nil sub_customer, "Subscription-only customer should appear in results"
    assert sub_customer[:margin].subscription_revenue_in_cents > 0
    assert_equal 0, sub_customer[:margin].event_revenue_in_cents
    assert_equal 0, sub_customer[:margin].cost_in_cents
  end
end
