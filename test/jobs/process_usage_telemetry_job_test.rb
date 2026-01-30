require "test_helper"

class ProcessUsageTelemetryJobTest < ActiveSupport::TestCase
  test "processes pending event through customer_linked to processed" do
    event = usage_telemetry_events(:pending_event)
    assert_equal "pending", event.status

    ProcessUsageTelemetryJob.perform_now(event.id)

    event.reload
    assert_equal "processed", event.status
    assert_not_nil event.customer_id

    # org-specific rate: input=2.5/1k, output=5.0/1k
    # cost = (1000 * 2.5 / 1000) + (500 * 5.0 / 1000) = 2.5 + 2.5 = 5.0
    assert_equal BigDecimal("5.0"), event.total_cost_in_cents
    assert_equal BigDecimal("495.0"), event.margin_in_cents
    assert_equal 1, event.cost_entries.count
    assert_equal "openai", event.cost_entries.first.vendor_name
  end

  test "finds or creates customer by external_id" do
    org = organizations(:acme)
    event = org.usage_telemetry_events.create!(
      unique_request_token: "req_new_customer_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_brand_new",
      customer_name: "Brand New Customer",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 2000,
      vendor_costs_raw: [ { "vendor_name" => "openai", "ai_model_name" => "gpt-4", "input_tokens" => 1000, "output_tokens" => 500, "unit_count" => 1500, "unit_type" => "tokens" } ],
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
      revenue_amount_in_cents: 1,
      vendor_costs_raw: [ { "vendor_name" => "openai", "ai_model_name" => "gpt-4", "input_tokens" => 10000, "output_tokens" => 5000, "unit_count" => 15000, "unit_type" => "tokens" } ],
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

    # Clear existing unacknowledged below_threshold alert for this customer
    MarginAlert.where(customer: customers(:customer_one), alert_type: "below_threshold", acknowledged_at: nil).delete_all

    event = org.usage_telemetry_events.create!(
      unique_request_token: "req_low_margin_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_costs_raw: [ { "vendor_name" => "openai", "ai_model_name" => "gpt-4", "input_tokens" => 110000, "output_tokens" => 50000, "unit_count" => 160000, "unit_type" => "tokens" } ],
      occurred_at: Time.current
    )

    assert_difference "MarginAlert.count", 1 do
      ProcessUsageTelemetryJob.perform_now(event.id)
    end

    alert = MarginAlert.last
    assert_equal "below_threshold", alert.alert_type
  end

  test "does not duplicate alerts for same customer and type" do
    org = organizations(:acme)
    customer = customers(:customer_one)

    MarginAlert.create!(
      organization: org,
      customer: customer,
      alert_type: "negative_margin",
      message: "Existing unacknowledged alert"
    )

    event = org.usage_telemetry_events.create!(
      unique_request_token: "req_dedup_#{SecureRandom.hex(4)}",
      customer_external_id: customer.external_id,
      customer_name: customer.name,
      event_type: "expensive_op",
      revenue_amount_in_cents: 1,
      vendor_costs_raw: [ { "vendor_name" => "openai", "ai_model_name" => "gpt-4", "input_tokens" => 10000, "output_tokens" => 5000, "unit_count" => 15000, "unit_type" => "tokens" } ],
      occurred_at: Time.current
    )

    assert_no_difference "MarginAlert.count" do
      ProcessUsageTelemetryJob.perform_now(event.id)
    end
  end

  test "customer_linked status survives and resumes at process_costs" do
    org = organizations(:acme)
    event = org.usage_telemetry_events.create!(
      unique_request_token: "req_resume_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_costs_raw: [ { "vendor_name" => "openai", "ai_model_name" => "gpt-4", "input_tokens" => 1000, "output_tokens" => 500, "unit_count" => 1500, "unit_type" => "tokens" } ],
      occurred_at: Time.current,
      customer: customers(:customer_one),
      status: "customer_linked"
    )

    ProcessUsageTelemetryJob.perform_now(event.id)

    event.reload
    assert_equal "processed", event.status
    assert event.cost_entries.any?
  end
end
