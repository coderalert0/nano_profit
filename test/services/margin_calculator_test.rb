require "test_helper"

class MarginCalculatorTest < ActiveSupport::TestCase
  test "organization_margin returns correct totals" do
    org = organizations(:acme)
    result = MarginCalculator.organization_margin(org)

    assert_equal 1000, result.revenue_in_cents
    assert_equal 500, result.cost_in_cents
    assert_equal 500, result.margin_in_cents
    assert_equal 5000, result.margin_bps # 50%
  end

  test "customer_margin returns correct totals" do
    customer = customers(:customer_one)
    result = MarginCalculator.customer_margin(customer)

    assert_equal 1000, result.revenue_in_cents
    assert_equal 500, result.cost_in_cents
    assert_equal 500, result.margin_in_cents
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

    assert_equal 450, breakdown["openai"]
    assert_equal 50, breakdown["aws"]
  end

  test "organization_margin with time period filter" do
    org = organizations(:acme)
    result = MarginCalculator.organization_margin(org, 2.hours.ago..Time.current)

    assert_equal 1000, result.revenue_in_cents
  end

  test "customer_margins returns per-customer breakdown" do
    org = organizations(:acme)
    margins = MarginCalculator.customer_margins(org)

    assert_equal 1, margins.length
    cm = margins.first
    assert_equal "Customer One", cm[:customer_name]
    assert_equal 1000, cm[:margin].revenue_in_cents
    assert_equal 5000, cm[:margin].margin_bps
  end

  test "integer arithmetic only - no floating point in margin_bps" do
    org = organizations(:acme)
    result = MarginCalculator.organization_margin(org)

    assert_kind_of Integer, result.margin_bps
    assert_kind_of Integer, result.revenue_in_cents
    assert_kind_of Integer, result.cost_in_cents
    assert_kind_of Integer, result.margin_in_cents
  end
end
