require "test_helper"

class ProcessEventJobTest < ActiveSupport::TestCase
  test "processes pending event through customer_linked to processed" do
    event = events(:pending_event)
    assert_equal "pending", event.status

    ProcessEventJob.perform_now(event.id)

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
    event = org.events.create!(
      unique_request_token: "req_new_customer_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_brand_new",
      customer_name: "Brand New Customer",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 2000,
      vendor_costs_raw: [ { "vendor_name" => "openai", "ai_model_name" => "gpt-4", "input_tokens" => 1000, "output_tokens" => 500, "unit_count" => 1500, "unit_type" => "tokens" } ],
      occurred_at: Time.current
    )

    assert_difference "Customer.count", 1 do
      ProcessEventJob.perform_now(event.id)
    end

    event.reload
    assert_equal "Brand New Customer", event.customer.name
    assert_equal "cust_brand_new", event.customer.external_id
  end

  test "does not reprocess already processed event" do
    event = events(:processed_event)
    original_cost = event.total_cost_in_cents

    ProcessEventJob.perform_now(event.id)

    assert_equal original_cost, event.reload.total_cost_in_cents
  end

  test "customer_linked status survives and resumes at process_costs" do
    org = organizations(:acme)
    event = org.events.create!(
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

    ProcessEventJob.perform_now(event.id)

    event.reload
    assert_equal "processed", event.status
    assert event.cost_entries.any?
  end

  test "transient errors leave status unchanged for retry" do
    org = organizations(:acme)
    event = org.events.create!(
      unique_request_token: "req_transient_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_costs_raw: [ { "vendor_name" => "openai", "ai_model_name" => "gpt-4", "input_tokens" => 1000, "output_tokens" => 500, "unit_count" => 1500, "unit_type" => "tokens" } ],
      occurred_at: Time.current,
      customer: customers(:customer_one),
      status: "customer_linked"
    )

    # Temporarily override EventProcessor#call to raise a transient error
    original_call = EventProcessor.instance_method(:call)
    EventProcessor.define_method(:call) { raise ActiveRecord::ConnectionNotEstablished, "connection lost" }

    assert_raises(ActiveRecord::ConnectionNotEstablished) do
      ProcessEventJob.perform_now(event.id)
    end

    # Status should remain customer_linked (not failed)
    assert_equal "customer_linked", event.reload.status
  ensure
    EventProcessor.define_method(:call, original_call) if original_call
  end

  test "missing rate creates zero-cost entry and processes event" do
    org = organizations(:acme)
    event = org.events.create!(
      unique_request_token: "req_runtime_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_nonexistent",
      customer_name: "No Customer",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_costs_raw: [ { "vendor_name" => "unknown_vendor", "ai_model_name" => "unknown_model", "input_tokens" => 1000, "output_tokens" => 500, "unit_count" => 1500, "unit_type" => "tokens" } ],
      occurred_at: Time.current,
      customer: customers(:customer_one),
      status: "customer_linked"
    )

    ProcessEventJob.perform_now(event.id)

    event.reload
    assert_equal "processed", event.status
    assert_equal 0, event.total_cost_in_cents
    assert_equal 1, event.cost_entries.count
    assert_equal "missing_rate", event.cost_entries.first.metadata["rate_source"]
  end
end
