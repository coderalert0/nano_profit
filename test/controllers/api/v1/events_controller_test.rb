require "test_helper"

class Api::V1::EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:acme)
    @headers = {
      "Authorization" => "Bearer #{@org.api_key}",
      "Content-Type" => "application/json"
    }
  end

  test "returns 401 without api key" do
    post api_v1_events_url, params: {}.to_json,
      headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  test "returns 401 with invalid api key" do
    post api_v1_events_url, params: {}.to_json,
      headers: { "Authorization" => "Bearer invalid", "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  test "creates event and returns 202" do
    payload = {
      event: {
        unique_request_token: "req_new_#{SecureRandom.hex(8)}",
        customer_external_id: "cust_123",
        customer_name: "Acme Corp",
        event_type: "ai_analysis",
        revenue_amount_in_cents: 1000,
        vendor_costs: [
          { vendor_name: "openai", ai_model_name: "gpt-4", input_tokens: 15000, output_tokens: 1, unit_count: 15000, unit_type: "tokens" }
        ],
        metadata: { model: "gpt-4" },
        occurred_at: Time.current.iso8601
      }
    }

    assert_enqueued_with(job: ProcessEventJob) do
      post api_v1_events_url, params: payload.to_json, headers: @headers
    end

    assert_response :accepted
    json = JSON.parse(response.body)
    assert json["id"].present?
    assert_equal "pending", json["status"]
  end

  test "returns 200 for duplicate unique_request_token (idempotent)" do
    existing = events(:processed_event)
    payload = {
      event: {
        unique_request_token: existing.unique_request_token,
        customer_external_id: "cust_001",
        event_type: "ai_analysis",
        revenue_amount_in_cents: 1000,
        vendor_costs: []
      }
    }

    assert_no_enqueued_jobs do
      post api_v1_events_url, params: payload.to_json, headers: @headers
    end

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal existing.id, json["id"]
  end

  test "persists ai_model_name and token counts in vendor_costs_raw" do
    payload = {
      event: {
        unique_request_token: "req_rate_#{SecureRandom.hex(8)}",
        customer_external_id: "cust_123",
        customer_name: "Acme Corp",
        event_type: "ai_analysis",
        revenue_amount_in_cents: 1000,
        vendor_costs: [
          { vendor_name: "openai", ai_model_name: "gpt-4", amount_in_cents: 999, input_tokens: 2000, output_tokens: 500, unit_count: 2500, unit_type: "tokens" }
        ],
        occurred_at: Time.current.iso8601
      }
    }

    assert_enqueued_with(job: ProcessEventJob) do
      post api_v1_events_url, params: payload.to_json, headers: @headers
    end

    assert_response :accepted
    event = Event.find(JSON.parse(response.body)["id"])
    vc = event.vendor_costs_raw.first
    assert_equal "gpt-4", vc["ai_model_name"]
    assert_equal 2000, vc["input_tokens"]
    assert_equal 500, vc["output_tokens"]
  end

  test "rejects unrecognized model name with 422" do
    payload = {
      event: {
        unique_request_token: "req_reject_#{SecureRandom.hex(8)}",
        customer_external_id: "cust_123",
        customer_name: "Acme Corp",
        event_type: "ai_analysis",
        revenue_amount_in_cents: 1000,
        vendor_costs: [
          { vendor_name: "openai", ai_model_name: "gpt-nonexistent", input_tokens: 100, output_tokens: 1, unit_count: 1000, unit_type: "tokens" }
        ]
      }
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json["errors"].any? { |e| e.include?("Unrecognized vendor_name 'openai' with ai_model_name 'gpt-nonexistent'") }
  end

  test "rejects valid ai_model_name with wrong vendor_name" do
    payload = {
      event: {
        unique_request_token: "req_wrong_vendor_#{SecureRandom.hex(8)}",
        customer_external_id: "cust_123",
        customer_name: "Acme Corp",
        event_type: "ai_analysis",
        revenue_amount_in_cents: 1000,
        vendor_costs: [
          { vendor_name: "anthropic", ai_model_name: "gpt-4", input_tokens: 100, output_tokens: 1, unit_count: 1000, unit_type: "tokens" }
        ]
      }
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json["errors"].any? { |e| e.include?("Unrecognized vendor_name 'anthropic' with ai_model_name 'gpt-4'") }
  end

  test "accepts recognized model name" do
    payload = {
      event: {
        unique_request_token: "req_known_#{SecureRandom.hex(8)}",
        customer_external_id: "cust_123",
        customer_name: "Acme Corp",
        event_type: "ai_analysis",
        revenue_amount_in_cents: 1000,
        vendor_costs: [
          { vendor_name: "openai", ai_model_name: "gpt-4", input_tokens: 100, output_tokens: 1, unit_count: 1000, unit_type: "tokens" }
        ]
      }
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :accepted
  end

  test "rejects vendor_costs missing ai_model_name" do
    payload = {
      event: {
        unique_request_token: "req_nomodel_#{SecureRandom.hex(8)}",
        customer_external_id: "cust_123",
        customer_name: "Acme Corp",
        event_type: "send_campaign",
        revenue_amount_in_cents: 500,
        vendor_costs: [
          { vendor_name: "twilio", input_tokens: 0, output_tokens: 0, unit_count: 10, unit_type: "messages" }
        ]
      }
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json["errors"].any? { |e| e.include?("Missing ai_model_name") }
  end

  test "rejects with multiple errors for multiple unrecognized models" do
    payload = {
      event: {
        unique_request_token: "req_multi_#{SecureRandom.hex(8)}",
        customer_external_id: "cust_123",
        customer_name: "Acme Corp",
        event_type: "ai_analysis",
        revenue_amount_in_cents: 1000,
        vendor_costs: [
          { vendor_name: "openai", ai_model_name: "gpt-fake", input_tokens: 100, output_tokens: 1, unit_count: 1000, unit_type: "tokens" },
          { vendor_name: "anthropic", ai_model_name: "claude-fake", input_tokens: 200, output_tokens: 1, unit_count: 500, unit_type: "tokens" }
        ]
      }
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json["errors"].any? { |e| e.include?("gpt-fake") }
    assert json["errors"].any? { |e| e.include?("claude-fake") }
  end

  test "returns 422 for missing required fields" do
    payload = {
      event: {
        unique_request_token: "req_incomplete"
      }
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
  end

  test "rejects negative input_tokens" do
    payload = {
      event: {
        unique_request_token: "req_neg_input_#{SecureRandom.hex(8)}",
        customer_external_id: "cust_123",
        customer_name: "Acme Corp",
        event_type: "ai_analysis",
        revenue_amount_in_cents: 1000,
        vendor_costs: [
          { vendor_name: "openai", ai_model_name: "gpt-4", input_tokens: -100, output_tokens: 500, unit_count: 1000, unit_type: "tokens" }
        ]
      }
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json["errors"].any? { |e| e.include?("Negative input_tokens") }
  end

  test "rejects negative output_tokens" do
    payload = {
      event: {
        unique_request_token: "req_neg_output_#{SecureRandom.hex(8)}",
        customer_external_id: "cust_123",
        customer_name: "Acme Corp",
        event_type: "ai_analysis",
        revenue_amount_in_cents: 1000,
        vendor_costs: [
          { vendor_name: "openai", ai_model_name: "gpt-4", input_tokens: 100, output_tokens: -500, unit_count: 1000, unit_type: "tokens" }
        ]
      }
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json["errors"].any? { |e| e.include?("Negative output_tokens") }
  end

  test "rejects zero input and output tokens" do
    payload = {
      event: {
        unique_request_token: "req_zero_both_#{SecureRandom.hex(8)}",
        customer_external_id: "cust_123",
        customer_name: "Acme Corp",
        event_type: "ai_analysis",
        revenue_amount_in_cents: 1000,
        vendor_costs: [
          { vendor_name: "openai", ai_model_name: "gpt-4", input_tokens: 0, output_tokens: 0, unit_count: 0, unit_type: "tokens" }
        ]
      }
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json["errors"].any? { |e| e.include?("Both input_tokens and output_tokens are zero or missing") }
  end
end
