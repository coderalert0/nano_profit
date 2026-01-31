require "test_helper"

class EventProcessorTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:acme)
  end

  test "creates cost entry using vendor rate when rate is found" do
    event = @org.events.create!(
      unique_request_token: "req_rate_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_costs_raw: [ {
        "vendor_name" => "openai",
        "ai_model_name" => "gpt-4",
        "input_tokens" => 1000,
        "output_tokens" => 500,
        "unit_count" => 1500,
        "unit_type" => "tokens"
      } ],
      occurred_at: Time.current
    )

    entries = EventProcessor.new(event).call

    assert_equal 1, entries.size
    entry = entries.first

    # org-specific rate: input=2.5/1k, output=5.0/1k
    # cost = (1000 * 2.5 / 1000) + (500 * 5.0 / 1000) = 2.5 + 2.5 = 5.0
    assert_equal BigDecimal("5.0"), entry.amount_in_cents
    assert_equal "vendor_rate", entry.metadata["rate_source"]
    assert_equal "gpt-4", entry.metadata["ai_model_name"]
    assert_equal "2.5", entry.metadata["input_rate_per_1k"]
    assert_equal "5.0", entry.metadata["output_rate_per_1k"]
  end

  test "raises when no rate found for vendor and ai_model_name" do
    event = @org.events.create!(
      unique_request_token: "req_no_rate_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 500,
      vendor_costs_raw: [ {
        "vendor_name" => "unknown_vendor",
        "ai_model_name" => "unknown_model",
        "input_tokens" => 100,
        "output_tokens" => 50,
        "unit_count" => 150,
        "unit_type" => "tokens"
      } ],
      occurred_at: Time.current
    )

    assert_raises(EventProcessor::RateNotFoundError) do
      EventProcessor.new(event).call
    end
  end

  test "processes multiple vendor cost entries" do
    event = @org.events.create!(
      unique_request_token: "req_multi_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 2000,
      vendor_costs_raw: [
        {
          "vendor_name" => "openai",
          "ai_model_name" => "gpt-4",
          "input_tokens" => 1000,
          "output_tokens" => 500,
          "unit_count" => 1500,
          "unit_type" => "tokens"
        },
        {
          "vendor_name" => "anthropic",
          "ai_model_name" => "claude-3",
          "input_tokens" => 2000,
          "output_tokens" => 1000,
          "unit_count" => 3000,
          "unit_type" => "tokens"
        }
      ],
      occurred_at: Time.current
    )

    entries = EventProcessor.new(event).call

    assert_equal 2, entries.size
    assert entries.all? { |e| e.metadata["rate_source"] == "vendor_rate" }
  end

  test "returns empty array for blank vendor_costs_raw" do
    event = @org.events.create!(
      unique_request_token: "req_empty_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "simple_event",
      revenue_amount_in_cents: 100,
      vendor_costs_raw: [],
      occurred_at: Time.current
    )

    entries = EventProcessor.new(event).call
    assert_equal [], entries
  end

  test "uses global rate when no org-specific rate exists" do
    event = @org.events.create!(
      unique_request_token: "req_global_rate_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_costs_raw: [ {
        "vendor_name" => "anthropic",
        "ai_model_name" => "claude-3",
        "input_tokens" => 1000,
        "output_tokens" => 500,
        "unit_count" => 1500,
        "unit_type" => "tokens"
      } ],
      occurred_at: Time.current
    )

    entries = EventProcessor.new(event).call

    assert_equal 1, entries.size
    entry = entries.first
    # global rate: input=1.5/1k, output=7.5/1k
    # cost = (1000 * 1.5 / 1000) + (500 * 7.5 / 1000) = 1.5 + 3.75 = 5.25
    assert_equal BigDecimal("5.25"), entry.amount_in_cents
    assert_equal "vendor_rate", entry.metadata["rate_source"]
  end

  test "handles zero token counts gracefully" do
    event = @org.events.create!(
      unique_request_token: "req_zero_tokens_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 100,
      vendor_costs_raw: [ {
        "vendor_name" => "openai",
        "ai_model_name" => "gpt-4",
        "unit_count" => 0,
        "unit_type" => "tokens"
      } ],
      occurred_at: Time.current
    )

    entries = EventProcessor.new(event).call

    assert_equal 1, entries.size
    assert_equal BigDecimal("0"), entries.first.amount_in_cents
  end

  test "uses deactivated global rate for processing (find_rate_for_processing)" do
    # Deactivate the global rate for gpt-3.5 (already inactive in fixtures)
    inactive = vendor_rates(:inactive_rate)
    assert_not inactive.active?

    event = @org.events.create!(
      unique_request_token: "req_deactivated_#{SecureRandom.hex(4)}",
      customer_external_id: "cust_001",
      customer_name: "Customer One",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_costs_raw: [ {
        "vendor_name" => "openai",
        "ai_model_name" => "gpt-3.5",
        "input_tokens" => 1000,
        "output_tokens" => 500,
        "unit_count" => 1500,
        "unit_type" => "tokens"
      } ],
      occurred_at: Time.current
    )

    entries = EventProcessor.new(event).call

    assert_equal 1, entries.size
    # inactive rate: input=0.05/1k, output=0.15/1k
    # cost = (1000 * 0.05 / 1000) + (500 * 0.15 / 1000) = 0.05 + 0.075 = 0.125
    assert_equal BigDecimal("0.125"), entries.first.amount_in_cents
  end
end
