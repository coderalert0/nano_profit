require "test_helper"

class Api::V1::TelemetryEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:acme)
    @headers = {
      "Authorization" => "Bearer #{@org.api_key}",
      "Content-Type" => "application/json"
    }
  end

  test "returns 401 without api key" do
    post api_v1_telemetry_events_url, params: {}.to_json,
      headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  test "returns 401 with invalid api key" do
    post api_v1_telemetry_events_url, params: {}.to_json,
      headers: { "Authorization" => "Bearer invalid", "Content-Type" => "application/json" }
    assert_response :unauthorized
  end

  test "creates event and returns 202" do
    payload = {
      telemetry_event: {
        unique_request_token: "req_new_#{SecureRandom.hex(8)}",
        customer_external_id: "cust_123",
        customer_name: "Acme Corp",
        event_type: "ai_analysis",
        revenue_amount_in_cents: 1000,
        vendor_costs: [
          { vendor_name: "openai", amount_in_cents: 450, unit_count: 15000, unit_type: "tokens" }
        ],
        metadata: { model: "gpt-4" },
        occurred_at: Time.current.iso8601
      }
    }

    assert_enqueued_with(job: ProcessUsageTelemetryJob) do
      post api_v1_telemetry_events_url, params: payload.to_json, headers: @headers
    end

    assert_response :accepted
    json = JSON.parse(response.body)
    assert json["id"].present?
    assert_equal "pending", json["status"]
  end

  test "returns 200 for duplicate unique_request_token (idempotent)" do
    existing = usage_telemetry_events(:processed_event)
    payload = {
      telemetry_event: {
        unique_request_token: existing.unique_request_token,
        customer_external_id: "cust_001",
        event_type: "ai_analysis",
        revenue_amount_in_cents: 1000,
        vendor_costs: []
      }
    }

    assert_no_enqueued_jobs do
      post api_v1_telemetry_events_url, params: payload.to_json, headers: @headers
    end

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal existing.id, json["id"]
  end

  test "returns 422 for missing required fields" do
    payload = {
      telemetry_event: {
        unique_request_token: "req_incomplete"
      }
    }

    post api_v1_telemetry_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
  end
end
