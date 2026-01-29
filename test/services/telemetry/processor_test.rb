require "test_helper"

class Telemetry::ProcessorTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:acme)
  end

  test "creates cost entry using vendor rate when rate is found" do
    event = @org.usage_telemetry_events.create!(
      unique_request_token: "req_rate_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_costs_raw: [ {
        "vendor_name" => "openai",
        "ai_model_name" => "gpt-4",
        "amount_in_cents" => 999,
        "input_tokens" => 1000,
        "output_tokens" => 500,
        "unit_count" => 1500,
        "unit_type" => "tokens"
      } ],
      occurred_at: Time.current
    )

    entries = Telemetry::Processor.new(event).call

    assert_equal 1, entries.size
    entry = entries.first

    # org-specific rate: input=2.5/1k, output=5.0/1k
    # cost = (1000 * 2.5 / 1000) + (500 * 5.0 / 1000) = 2.5 + 2.5 = 5.0
    assert_equal BigDecimal("5.0"), entry.amount_in_cents
    assert_equal "vendor_rate", entry.metadata["rate_source"]
    assert_equal "gpt-4", entry.metadata["ai_model_name"]
  end

  test "falls back to raw amount when no rate found" do
    event = @org.usage_telemetry_events.create!(
      unique_request_token: "req_fallback_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "send_campaign",
      revenue_amount_in_cents: 500,
      vendor_costs_raw: [ {
        "vendor_name" => "twilio",
        "amount_in_cents" => 200,
        "unit_count" => 10,
        "unit_type" => "messages"
      } ],
      occurred_at: Time.current
    )

    entries = Telemetry::Processor.new(event).call

    assert_equal 1, entries.size
    entry = entries.first
    assert_equal BigDecimal("200"), entry.amount_in_cents
    assert_equal "raw_fallback", entry.metadata["rate_source"]
  end

  test "falls back to raw when ai_model_name is missing" do
    event = @org.usage_telemetry_events.create!(
      unique_request_token: "req_no_model_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_costs_raw: [ {
        "vendor_name" => "openai",
        "amount_in_cents" => 300,
        "unit_count" => 5000,
        "unit_type" => "tokens"
      } ],
      occurred_at: Time.current
    )

    entries = Telemetry::Processor.new(event).call

    assert_equal 1, entries.size
    assert_equal "raw_fallback", entries.first.metadata["rate_source"]
  end

  test "reads ai_model_name from event metadata when not in vendor entry" do
    event = @org.usage_telemetry_events.create!(
      unique_request_token: "req_meta_model_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_costs_raw: [ {
        "vendor_name" => "openai",
        "amount_in_cents" => 999,
        "input_tokens" => 2000,
        "output_tokens" => 1000,
        "unit_count" => 3000,
        "unit_type" => "tokens"
      } ],
      metadata: { "ai_model_name" => "gpt-4" },
      occurred_at: Time.current
    )

    entries = Telemetry::Processor.new(event).call

    assert_equal 1, entries.size
    entry = entries.first
    # org-specific rate: input=2.5/1k, output=5.0/1k
    # cost = (2000 * 2.5 / 1000) + (1000 * 5.0 / 1000) = 5.0 + 5.0 = 10.0
    assert_equal BigDecimal("10.0"), entry.amount_in_cents
    assert_equal "vendor_rate", entry.metadata["rate_source"]
  end

  test "processes multiple vendor cost entries" do
    event = @org.usage_telemetry_events.create!(
      unique_request_token: "req_multi_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 2000,
      vendor_costs_raw: [
        {
          "vendor_name" => "openai",
          "ai_model_name" => "gpt-4",
          "amount_in_cents" => 999,
          "input_tokens" => 1000,
          "output_tokens" => 500,
          "unit_count" => 1500,
          "unit_type" => "tokens"
        },
        {
          "vendor_name" => "twilio",
          "amount_in_cents" => 100,
          "unit_count" => 5,
          "unit_type" => "messages"
        }
      ],
      occurred_at: Time.current
    )

    entries = Telemetry::Processor.new(event).call

    assert_equal 2, entries.size
    assert_equal "vendor_rate", entries.first.metadata["rate_source"]
    assert_equal "raw_fallback", entries.second.metadata["rate_source"]
  end

  test "returns empty array for blank vendor_costs_raw" do
    event = @org.usage_telemetry_events.create!(
      unique_request_token: "req_empty_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "simple_event",
      revenue_amount_in_cents: 100,
      vendor_costs_raw: [],
      occurred_at: Time.current
    )

    entries = Telemetry::Processor.new(event).call
    assert_equal [], entries
  end

  test "records zero cost tagged no_rate_or_amount when no rate and no amount_in_cents" do
    event = @org.usage_telemetry_events.create!(
      unique_request_token: "req_no_rate_no_amt_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "send_campaign",
      revenue_amount_in_cents: 500,
      vendor_costs_raw: [ {
        "vendor_name" => "twilio",
        "unit_count" => 10,
        "unit_type" => "messages"
      } ],
      occurred_at: Time.current
    )

    entries = Telemetry::Processor.new(event).call

    assert_equal 1, entries.size
    entry = entries.first
    assert_equal BigDecimal("0"), entry.amount_in_cents
    assert_equal "no_rate_or_amount", entry.metadata["rate_source"]
  end

  test "uses global rate when no org-specific rate exists" do
    event = @org.usage_telemetry_events.create!(
      unique_request_token: "req_global_rate_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_costs_raw: [ {
        "vendor_name" => "anthropic",
        "ai_model_name" => "claude-3",
        "amount_in_cents" => 999,
        "input_tokens" => 1000,
        "output_tokens" => 500,
        "unit_count" => 1500,
        "unit_type" => "tokens"
      } ],
      occurred_at: Time.current
    )

    entries = Telemetry::Processor.new(event).call

    assert_equal 1, entries.size
    entry = entries.first
    # global rate: input=1.5/1k, output=7.5/1k
    # cost = (1000 * 1.5 / 1000) + (500 * 7.5 / 1000) = 1.5 + 3.75 = 5.25
    assert_equal BigDecimal("5.25"), entry.amount_in_cents
    assert_equal "vendor_rate", entry.metadata["rate_source"]
  end
end
