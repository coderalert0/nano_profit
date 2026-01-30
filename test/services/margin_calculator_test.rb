require "test_helper"

class MarginCalculatorTest < ActiveSupport::TestCase
  test "organization_margin returns correct totals including prorated subscription revenue" do
    org = organizations(:acme)
    result = MarginCalculator.organization_margin(org)

    # Event revenue: 1000 (processed_event) + 0 (subscription_customer_event) = 1000
    # Subscription revenue is prorated based on event date range (not full month)
    # Events occurred ~1 hour ago, so range is very short
    # With a tiny period, sub_revenue will be near 0
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
    assert result.subscription_revenue_in_cents >= 0
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
    [result.revenue_in_cents, result.cost_in_cents, result.margin_in_cents].each do |val|
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
end
