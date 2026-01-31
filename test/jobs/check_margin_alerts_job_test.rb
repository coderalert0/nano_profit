require "test_helper"

class CheckMarginAlertsJobTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:acme)
    @org.update!(margin_alert_threshold_bps: 5000, margin_alert_period_days: 7)
    # Clear fixture data that interferes with aggregate calculations
    MarginAlert.delete_all
    CostEntry.where(event_id: @org.events.select(:id)).delete_all
    @org.events.delete_all
  end

  test "creates negative margin alert for event type with negative aggregate margin" do
    customer = customers(:customer_one)
    @org.events.create!(
      unique_request_token: "req_neg_et_#{SecureRandom.hex(4)}",
      customer_external_id: customer.external_id,
      customer_name: customer.name,
      event_type: "expensive_op",
      revenue_amount_in_cents: 1,
      total_cost_in_cents: 100,
      margin_in_cents: -99,
      status: "processed",
      occurred_at: 1.day.ago,
      customer: customer,
      vendor_costs_raw: []
    )

    assert_difference "MarginAlert.where(dimension: 'event_type').count", 1 do
      CheckMarginAlertsJob.perform_now(@org.id)
    end

    alert = MarginAlert.find_by(dimension: "event_type", dimension_value: "expensive_op")
    assert_equal "negative_margin", alert.alert_type
    assert_includes alert.message, "expensive_op"
  end

  test "creates below threshold alert for customer below threshold" do
    customer = customers(:customer_one)
    @org.events.create!(
      unique_request_token: "req_low_cust_#{SecureRandom.hex(4)}",
      customer_external_id: customer.external_id,
      customer_name: customer.name,
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      total_cost_in_cents: 800,
      margin_in_cents: 200,
      status: "processed",
      occurred_at: 1.day.ago,
      customer: customer,
      vendor_costs_raw: []
    )

    assert_difference "MarginAlert.where(dimension: 'customer').count", 1 do
      CheckMarginAlertsJob.perform_now(@org.id)
    end

    alert = MarginAlert.find_by(dimension: "customer", dimension_value: customer.id.to_s)
    assert_equal "below_threshold", alert.alert_type
    assert_includes alert.message, customer.name
  end

  test "does not duplicate unacknowledged alerts" do
    customer = customers(:customer_one)
    @org.events.create!(
      unique_request_token: "req_dedup_#{SecureRandom.hex(4)}",
      customer_external_id: customer.external_id,
      customer_name: customer.name,
      event_type: "expensive_op",
      revenue_amount_in_cents: 1,
      total_cost_in_cents: 100,
      margin_in_cents: -99,
      status: "processed",
      occurred_at: 1.day.ago,
      customer: customer,
      vendor_costs_raw: []
    )

    # First run creates alerts
    CheckMarginAlertsJob.perform_now(@org.id)
    count_after_first = MarginAlert.count

    # Second run should not create duplicates
    assert_no_difference "MarginAlert.count" do
      CheckMarginAlertsJob.perform_now(@org.id)
    end
  end

  test "does nothing when threshold is 0" do
    @org.update!(margin_alert_threshold_bps: 0)

    customer = customers(:customer_one)
    @org.events.create!(
      unique_request_token: "req_zero_#{SecureRandom.hex(4)}",
      customer_external_id: customer.external_id,
      customer_name: customer.name,
      event_type: "expensive_op",
      revenue_amount_in_cents: 1,
      total_cost_in_cents: 100,
      margin_in_cents: -99,
      status: "processed",
      occurred_at: 1.day.ago,
      customer: customer,
      vendor_costs_raw: []
    )

    assert_no_difference "MarginAlert.count" do
      CheckMarginAlertsJob.perform_now(@org.id)
    end
  end

  test "respects configured period_days" do
    @org.update!(margin_alert_period_days: 3)

    customer = customers(:customer_one)
    # Event outside the 3-day window
    @org.events.create!(
      unique_request_token: "req_old_#{SecureRandom.hex(4)}",
      customer_external_id: customer.external_id,
      customer_name: customer.name,
      event_type: "expensive_op",
      revenue_amount_in_cents: 1,
      total_cost_in_cents: 100,
      margin_in_cents: -99,
      status: "processed",
      occurred_at: 5.days.ago,
      customer: customer,
      vendor_costs_raw: []
    )

    # Should not alert because event is outside the 3-day window
    assert_no_difference "MarginAlert.count" do
      CheckMarginAlertsJob.perform_now(@org.id)
    end

    # Event inside the 3-day window
    @org.events.create!(
      unique_request_token: "req_recent_#{SecureRandom.hex(4)}",
      customer_external_id: customer.external_id,
      customer_name: customer.name,
      event_type: "expensive_op",
      revenue_amount_in_cents: 1,
      total_cost_in_cents: 100,
      margin_in_cents: -99,
      status: "processed",
      occurred_at: 1.day.ago,
      customer: customer,
      vendor_costs_raw: []
    )

    # Now should alert (event_type + customer dimensions)
    assert_difference "MarginAlert.count", 2 do
      CheckMarginAlertsJob.perform_now(@org.id)
    end

    assert MarginAlert.exists?(dimension: "event_type", dimension_value: "expensive_op")
    assert MarginAlert.exists?(dimension: "customer", dimension_value: customer.id.to_s)
  end
end
