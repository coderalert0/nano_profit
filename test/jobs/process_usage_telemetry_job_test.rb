require "test_helper"

class ProcessUsageTelemetryJobTest < ActiveSupport::TestCase
  test "processes pending event and creates cost entries" do
    event = usage_telemetry_events(:pending_event)
    assert_equal "pending", event.status

    ProcessUsageTelemetryJob.perform_now(event.id)

    event.reload
    assert_equal "processed", event.status
    assert_not_nil event.customer_id
    assert_equal 200, event.total_cost_in_cents
    assert_equal 300, event.margin_in_cents
    assert_equal 1, event.cost_entries.count
    assert_equal "twilio", event.cost_entries.first.vendor_name
  end

  test "finds or creates customer by external_id" do
    org = organizations(:acme)
    event = org.usage_telemetry_events.create!(
      unique_request_token: "req_new_customer_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_brand_new",
      customer_name: "Brand New Customer",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 2000,
      vendor_costs_raw: [ { "vendor_name" => "openai", "amount_in_cents" => 800, "unit_count" => 5000, "unit_type" => "tokens" } ],
      occurred_at: Time.current
    )

    assert_difference "Customer.count", 1 do
      ProcessUsageTelemetryJob.perform_now(event.id)
    end

    event.reload
    assert_equal "Brand New Customer", event.customer.name
    assert_equal "cust_brand_new", event.customer.external_id
  end

  test "does not reprocess already processed event" do
    event = usage_telemetry_events(:processed_event)
    original_cost = event.total_cost_in_cents

    ProcessUsageTelemetryJob.perform_now(event.id)

    assert_equal original_cost, event.reload.total_cost_in_cents
  end

  test "creates negative margin alert" do
    org = organizations(:acme)
    event = org.usage_telemetry_events.create!(
      unique_request_token: "req_negative_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "expensive_op",
      revenue_amount_in_cents: 100,
      vendor_costs_raw: [ { "vendor_name" => "openai", "amount_in_cents" => 500, "unit_count" => 10000, "unit_type" => "tokens" } ],
      occurred_at: Time.current
    )

    assert_difference "MarginAlert.count", 1 do
      ProcessUsageTelemetryJob.perform_now(event.id)
    end

    alert = MarginAlert.last
    assert_equal "negative_margin", alert.alert_type
  end

  test "creates below threshold alert" do
    org = organizations(:acme)
    org.update!(margin_alert_threshold_bps: 5000) # 50%

    event = org.usage_telemetry_events.create!(
      unique_request_token: "req_low_margin_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_costs_raw: [ { "vendor_name" => "openai", "amount_in_cents" => 600, "unit_count" => 5000, "unit_type" => "tokens" } ],
      occurred_at: Time.current
    )

    assert_difference "MarginAlert.count", 1 do
      ProcessUsageTelemetryJob.perform_now(event.id)
    end

    alert = MarginAlert.last
    assert_equal "below_threshold", alert.alert_type
  end
end
