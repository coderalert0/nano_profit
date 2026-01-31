require "test_helper"

class Api::V1::EventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @org = organizations(:acme)
    @headers = {
      "Authorization" => "Bearer #{@org.api_key}",
      "Content-Type" => "application/json"
    }
  end

  # ── Auth ──────────────────────────────────────────────────────────

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

  # ── Batch basics ──────────────────────────────────────────────────

  test "creates batch of events and returns 200 with results array" do
    payload = {
      events: [
        valid_event_data("batch_1_#{SecureRandom.hex(8)}"),
        valid_event_data("batch_2_#{SecureRandom.hex(8)}")
      ]
    }

    assert_enqueued_jobs 2, only: ProcessEventJob do
      post api_v1_events_url, params: payload.to_json, headers: @headers
    end

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal 2, json["results"].size
    json["results"].each do |r|
      assert r["id"].present?
      assert_equal "created", r["status"]
    end
  end

  test "returns 400 for empty events array" do
    post api_v1_events_url, params: { events: [] }.to_json, headers: @headers
    assert_response :bad_request
  end

  test "returns 400 for missing events key" do
    post api_v1_events_url, params: {}.to_json, headers: @headers
    assert_response :bad_request
  end

  test "returns 413 for over 100 events" do
    events = 101.times.map { |i| valid_event_data("over_100_#{i}_#{SecureRandom.hex(4)}") }
    post api_v1_events_url, params: { events: events }.to_json, headers: @headers
    assert_response :payload_too_large
  end

  # ── Single event in batch ─────────────────────────────────────────

  test "creates single event in batch and returns 200" do
    payload = {
      events: [ valid_event_data("single_#{SecureRandom.hex(8)}") ]
    }

    assert_enqueued_with(job: ProcessEventJob) do
      post api_v1_events_url, params: payload.to_json, headers: @headers
    end

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal 1, json["results"].size
    assert json["results"][0]["id"].present?
    assert_equal "created", json["results"][0]["status"]
  end

  # ── Idempotency / duplicates ──────────────────────────────────────

  test "returns 200 with duplicate status for existing token" do
    existing = events(:processed_event)
    payload = {
      events: [
        {
          unique_request_token: existing.unique_request_token,
          customer_external_id: "cust_001",
          event_type: "ai_analysis",
          revenue_amount_in_cents: 1000,
          vendor_responses: []
        }
      ]
    }

    assert_no_enqueued_jobs do
      post api_v1_events_url, params: payload.to_json, headers: @headers
    end

    assert_response :ok
    json = JSON.parse(response.body)
    assert_equal existing.id, json["results"][0]["id"]
    assert_equal "duplicate", json["results"][0]["status"]
  end

  # ── Vendor response persistence ────────────────────────────────────

  test "persists normalized vendor costs from OpenAI raw_response" do
    payload = {
      events: [
        {
          unique_request_token: "req_rate_#{SecureRandom.hex(8)}",
          customer_external_id: "cust_123",
          customer_name: "Acme Corp",
          event_type: "ai_analysis",
          revenue_amount_in_cents: 1000,
          vendor_responses: [
            {
              vendor_name: "openai",
              raw_response: {
                model: "gpt-4",
                usage: { prompt_tokens: 2000, completion_tokens: 500 }
              }
            }
          ],
          occurred_at: Time.current.iso8601
        }
      ]
    }

    assert_enqueued_with(job: ProcessEventJob) do
      post api_v1_events_url, params: payload.to_json, headers: @headers
    end

    assert_response :ok
    event = Event.find(JSON.parse(response.body)["results"][0]["id"])
    vc = event.vendor_costs_raw.first
    assert_equal "openai", vc["vendor_name"]
    assert_equal "gpt-4", vc["ai_model_name"]
    assert_equal 2000, vc["input_tokens"]
    assert_equal 500, vc["output_tokens"]
  end

  test "persists normalized vendor costs from Anthropic raw_response" do
    payload = {
      events: [
        {
          unique_request_token: "req_anthropic_#{SecureRandom.hex(8)}",
          customer_external_id: "cust_123",
          customer_name: "Acme Corp",
          event_type: "ai_analysis",
          revenue_amount_in_cents: 1000,
          vendor_responses: [
            {
              vendor_name: "anthropic",
              raw_response: {
                model: "claude-3",
                usage: { input_tokens: 800, output_tokens: 300 }
              }
            }
          ],
          occurred_at: Time.current.iso8601
        }
      ]
    }

    assert_enqueued_with(job: ProcessEventJob) do
      post api_v1_events_url, params: payload.to_json, headers: @headers
    end

    assert_response :ok
    event = Event.find(JSON.parse(response.body)["results"][0]["id"])
    vc = event.vendor_costs_raw.first
    assert_equal "anthropic", vc["vendor_name"]
    assert_equal "claude-3", vc["ai_model_name"]
    assert_equal 800, vc["input_tokens"]
    assert_equal 300, vc["output_tokens"]
  end

  test "persists multiple appended responses from one event" do
    payload = {
      events: [
        {
          unique_request_token: "req_multi_resp_#{SecureRandom.hex(8)}",
          customer_external_id: "cust_123",
          customer_name: "Acme Corp",
          event_type: "ai_analysis",
          revenue_amount_in_cents: 2000,
          vendor_responses: [
            {
              vendor_name: "openai",
              raw_response: {
                model: "gpt-4",
                usage: { prompt_tokens: 1000, completion_tokens: 200 }
              }
            },
            {
              vendor_name: "openai",
              raw_response: {
                model: "gpt-4",
                usage: { prompt_tokens: 500, completion_tokens: 100 }
              }
            }
          ],
          occurred_at: Time.current.iso8601
        }
      ]
    }

    assert_enqueued_with(job: ProcessEventJob) do
      post api_v1_events_url, params: payload.to_json, headers: @headers
    end

    assert_response :ok
    event = Event.find(JSON.parse(response.body)["results"][0]["id"])
    assert_equal 2, event.vendor_costs_raw.size
    assert_equal 1000, event.vendor_costs_raw[0]["input_tokens"]
    assert_equal 500, event.vendor_costs_raw[1]["input_tokens"]
  end

  # ── Validation errors ─────────────────────────────────────────────

  test "rejects batch with all invalid events as 422" do
    payload = {
      events: [
        {
          unique_request_token: "req_reject_#{SecureRandom.hex(8)}",
          customer_external_id: "cust_123",
          event_type: "ai_analysis",
          revenue_amount_in_cents: 1000,
          vendor_responses: [
            {
              vendor_name: "openai",
              raw_response: {
                model: "gpt-nonexistent",
                usage: { prompt_tokens: 100, completion_tokens: 1 }
              }
            }
          ]
        }
      ]
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json["results"][0]["errors"].any? { |e| e.include?("Unrecognized vendor_name 'openai' with ai_model_name 'gpt-nonexistent'") }
  end

  test "returns 207 for partial failure — mix of valid and invalid events" do
    payload = {
      events: [
        valid_event_data("partial_ok_#{SecureRandom.hex(8)}"),
        {
          unique_request_token: "partial_bad_#{SecureRandom.hex(8)}",
          customer_external_id: "cust_123",
          event_type: "ai_analysis",
          revenue_amount_in_cents: 1000,
          vendor_responses: [
            {
              vendor_name: "openai",
              raw_response: {
                model: "gpt-nonexistent",
                usage: { prompt_tokens: 100, completion_tokens: 1 }
              }
            }
          ]
        }
      ]
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :multi_status
    json = JSON.parse(response.body)
    assert_equal 2, json["results"].size
    assert_equal "created", json["results"][0]["status"]
    assert_equal "error", json["results"][1]["status"]
  end

  test "rejects valid ai_model_name with wrong vendor_name" do
    payload = {
      events: [
        {
          unique_request_token: "req_wrong_vendor_#{SecureRandom.hex(8)}",
          customer_external_id: "cust_123",
          event_type: "ai_analysis",
          revenue_amount_in_cents: 1000,
          vendor_responses: [
            {
              vendor_name: "anthropic",
              raw_response: {
                model: "gpt-4",
                usage: { input_tokens: 100, output_tokens: 1 }
              }
            }
          ]
        }
      ]
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json["results"][0]["errors"].any? { |e| e.include?("Unrecognized vendor_name 'anthropic' with ai_model_name 'gpt-4'") }
  end

  test "accepts recognized model name" do
    payload = {
      events: [ valid_event_data("req_known_#{SecureRandom.hex(8)}") ]
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :ok
  end

  test "rejects unsupported vendor with error" do
    payload = {
      events: [
        {
          unique_request_token: "req_unsupported_#{SecureRandom.hex(8)}",
          customer_external_id: "cust_123",
          event_type: "ai_analysis",
          revenue_amount_in_cents: 1000,
          vendor_responses: [
            {
              vendor_name: "unknown_vendor",
              raw_response: { model: "some-model", usage: { prompt_tokens: 10, completion_tokens: 5 } }
            }
          ]
        }
      ]
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json["results"][0]["errors"].any? { |e| e.include?("Unknown vendor") }
  end

  test "rejects vendor_responses with empty raw_response resolving to missing model" do
    payload = {
      events: [
        {
          unique_request_token: "req_nomodel_#{SecureRandom.hex(8)}",
          customer_external_id: "cust_123",
          event_type: "send_campaign",
          revenue_amount_in_cents: 500,
          vendor_responses: [
            {
              vendor_name: "openai",
              raw_response: {}
            }
          ]
        }
      ]
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json["results"][0]["errors"].any? { |e| e.include?("Unrecognized vendor_name") }
  end

  test "rejects with multiple errors for multiple unrecognized models" do
    payload = {
      events: [
        {
          unique_request_token: "req_multi_#{SecureRandom.hex(8)}",
          customer_external_id: "cust_123",
          event_type: "ai_analysis",
          revenue_amount_in_cents: 1000,
          vendor_responses: [
            {
              vendor_name: "openai",
              raw_response: {
                model: "gpt-fake",
                usage: { prompt_tokens: 100, completion_tokens: 1 }
              }
            },
            {
              vendor_name: "anthropic",
              raw_response: {
                model: "claude-fake",
                usage: { input_tokens: 200, output_tokens: 1 }
              }
            }
          ]
        }
      ]
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json["results"][0]["errors"].any? { |e| e.include?("gpt-fake") }
    assert json["results"][0]["errors"].any? { |e| e.include?("claude-fake") }
  end

  test "returns 422 for missing required fields" do
    payload = {
      events: [
        { unique_request_token: "req_incomplete" }
      ]
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
  end

  test "rejects negative input_tokens from raw_response" do
    payload = {
      events: [
        {
          unique_request_token: "req_neg_input_#{SecureRandom.hex(8)}",
          customer_external_id: "cust_123",
          event_type: "ai_analysis",
          revenue_amount_in_cents: 1000,
          vendor_responses: [
            {
              vendor_name: "openai",
              raw_response: {
                model: "gpt-4",
                usage: { prompt_tokens: -100, completion_tokens: 500 }
              }
            }
          ]
        }
      ]
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json["results"][0]["errors"].any? { |e| e.include?("Negative input_tokens") }
  end

  test "rejects negative output_tokens from raw_response" do
    payload = {
      events: [
        {
          unique_request_token: "req_neg_output_#{SecureRandom.hex(8)}",
          customer_external_id: "cust_123",
          event_type: "ai_analysis",
          revenue_amount_in_cents: 1000,
          vendor_responses: [
            {
              vendor_name: "openai",
              raw_response: {
                model: "gpt-4",
                usage: { prompt_tokens: 100, completion_tokens: -500 }
              }
            }
          ]
        }
      ]
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json["results"][0]["errors"].any? { |e| e.include?("Negative output_tokens") }
  end

  test "rejects zero input and output tokens from raw_response" do
    payload = {
      events: [
        {
          unique_request_token: "req_zero_both_#{SecureRandom.hex(8)}",
          customer_external_id: "cust_123",
          event_type: "ai_analysis",
          revenue_amount_in_cents: 1000,
          vendor_responses: [
            {
              vendor_name: "openai",
              raw_response: {
                model: "gpt-4",
                usage: { prompt_tokens: 0, completion_tokens: 0 }
              }
            }
          ]
        }
      ]
    }

    post api_v1_events_url, params: payload.to_json, headers: @headers
    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert json["results"][0]["errors"].any? { |e| e.include?("Both input_tokens and output_tokens are zero or missing") }
  end

  private

  def valid_event_data(token)
    {
      unique_request_token: token,
      customer_external_id: "cust_123",
      customer_name: "Acme Corp",
      event_type: "ai_analysis",
      revenue_amount_in_cents: 1000,
      vendor_responses: [
        {
          vendor_name: "openai",
          raw_response: {
            model: "gpt-4",
            usage: { prompt_tokens: 15000, completion_tokens: 1 }
          }
        }
      ],
      metadata: { model: "gpt-4" },
      occurred_at: Time.current.iso8601
    }
  end
end
