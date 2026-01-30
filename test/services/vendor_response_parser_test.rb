require "test_helper"

class VendorResponseParserTest < ActiveSupport::TestCase
  # ── OpenAI-compatible ──────────────────────────────────────────────

  test "parses OpenAI response" do
    result = VendorResponseParser.call(
      vendor_name: "openai",
      raw_response: {
        "model" => "gpt-4",
        "usage" => { "prompt_tokens" => 100, "completion_tokens" => 50 }
      }
    )

    assert_equal "openai", result["vendor_name"]
    assert_equal "gpt-4", result["ai_model_name"]
    assert_equal 100, result["input_tokens"]
    assert_equal 50, result["output_tokens"]
  end

  test "parses Groq response (OpenAI-compatible)" do
    result = VendorResponseParser.call(
      vendor_name: "groq",
      raw_response: {
        "model" => "llama-3.1-70b",
        "usage" => { "prompt_tokens" => 200, "completion_tokens" => 80 }
      }
    )

    assert_equal "groq", result["vendor_name"]
    assert_equal "llama-3.1-70b", result["ai_model_name"]
    assert_equal 200, result["input_tokens"]
    assert_equal 80, result["output_tokens"]
  end

  test "parses Azure response (OpenAI-compatible)" do
    result = VendorResponseParser.call(
      vendor_name: "azure",
      raw_response: {
        "model" => "gpt-4",
        "usage" => { "prompt_tokens" => 150, "completion_tokens" => 60 }
      }
    )

    assert_equal "azure", result["vendor_name"]
    assert_equal "gpt-4", result["ai_model_name"]
    assert_equal 150, result["input_tokens"]
    assert_equal 60, result["output_tokens"]
  end

  test "parses Together response (OpenAI-compatible)" do
    result = VendorResponseParser.call(
      vendor_name: "together",
      raw_response: {
        "model" => "mistralai/Mixtral-8x7B",
        "usage" => { "prompt_tokens" => 300, "completion_tokens" => 120 }
      }
    )

    assert_equal "together", result["vendor_name"]
    assert_equal "mistralai/Mixtral-8x7B", result["ai_model_name"]
  end

  test "parses Fireworks response (OpenAI-compatible)" do
    result = VendorResponseParser.call(
      vendor_name: "fireworks",
      raw_response: {
        "model" => "accounts/fireworks/models/llama-v3p1-70b",
        "usage" => { "prompt_tokens" => 250, "completion_tokens" => 100 }
      }
    )

    assert_equal "fireworks", result["vendor_name"]
    assert_equal 250, result["input_tokens"]
  end

  test "parses Mistral response (OpenAI-compatible)" do
    result = VendorResponseParser.call(
      vendor_name: "mistral",
      raw_response: {
        "model" => "mistral-large-latest",
        "usage" => { "prompt_tokens" => 180, "completion_tokens" => 70 }
      }
    )

    assert_equal "mistral", result["vendor_name"]
    assert_equal "mistral-large-latest", result["ai_model_name"]
  end

  # ── Anthropic-compatible ───────────────────────────────────────────

  test "parses Anthropic response" do
    result = VendorResponseParser.call(
      vendor_name: "anthropic",
      raw_response: {
        "model" => "claude-3-opus-20240229",
        "usage" => { "input_tokens" => 500, "output_tokens" => 200 }
      }
    )

    assert_equal "anthropic", result["vendor_name"]
    assert_equal "claude-3-opus-20240229", result["ai_model_name"]
    assert_equal 500, result["input_tokens"]
    assert_equal 200, result["output_tokens"]
  end

  test "parses Bedrock response (Anthropic-compatible)" do
    result = VendorResponseParser.call(
      vendor_name: "bedrock",
      raw_response: {
        "model" => "claude-3-sonnet-20240229",
        "usage" => { "input_tokens" => 400, "output_tokens" => 150 }
      }
    )

    assert_equal "bedrock", result["vendor_name"]
    assert_equal "claude-3-sonnet-20240229", result["ai_model_name"]
    assert_equal 400, result["input_tokens"]
    assert_equal 150, result["output_tokens"]
  end

  # ── Google-compatible ──────────────────────────────────────────────

  test "parses Google response with camelCase keys" do
    result = VendorResponseParser.call(
      vendor_name: "google",
      raw_response: {
        "modelVersion" => "gemini-1.5-pro",
        "usageMetadata" => { "promptTokenCount" => 300, "candidatesTokenCount" => 100 }
      }
    )

    assert_equal "google", result["vendor_name"]
    assert_equal "gemini-1.5-pro", result["ai_model_name"]
    assert_equal 300, result["input_tokens"]
    assert_equal 100, result["output_tokens"]
  end

  test "parses Google response with snake_case keys" do
    result = VendorResponseParser.call(
      vendor_name: "google",
      raw_response: {
        "model_version" => "gemini-1.5-flash",
        "usage_metadata" => { "prompt_token_count" => 250, "candidates_token_count" => 80 }
      }
    )

    assert_equal "google", result["vendor_name"]
    assert_equal "gemini-1.5-flash", result["ai_model_name"]
    assert_equal 250, result["input_tokens"]
    assert_equal 80, result["output_tokens"]
  end

  test "parses Gemini alias (Google-compatible)" do
    result = VendorResponseParser.call(
      vendor_name: "gemini",
      raw_response: {
        "modelVersion" => "gemini-2.0-flash",
        "usageMetadata" => { "promptTokenCount" => 100, "candidatesTokenCount" => 50 }
      }
    )

    assert_equal "gemini", result["vendor_name"]
    assert_equal "gemini-2.0-flash", result["ai_model_name"]
  end

  # ── Edge cases ─────────────────────────────────────────────────────

  test "handles missing usage fields gracefully" do
    result = VendorResponseParser.call(
      vendor_name: "openai",
      raw_response: { "model" => "gpt-4" }
    )

    assert_equal "gpt-4", result["ai_model_name"]
    assert_equal 0, result["input_tokens"]
    assert_equal 0, result["output_tokens"]
  end

  test "handles empty response" do
    result = VendorResponseParser.call(
      vendor_name: "openai",
      raw_response: {}
    )

    assert_equal "", result["ai_model_name"]
    assert_equal 0, result["input_tokens"]
    assert_equal 0, result["output_tokens"]
  end

  test "handles nil response" do
    result = VendorResponseParser.call(
      vendor_name: "openai",
      raw_response: nil
    )

    assert_equal "", result["ai_model_name"]
    assert_equal 0, result["input_tokens"]
    assert_equal 0, result["output_tokens"]
  end

  test "raises ParseError for unknown vendor" do
    error = assert_raises(VendorResponseParser::ParseError) do
      VendorResponseParser.call(
        vendor_name: "unknown_vendor",
        raw_response: { "model" => "test" }
      )
    end

    assert_includes error.message, "Unknown vendor: 'unknown_vendor'"
  end

  test "normalizes vendor name to lowercase" do
    result = VendorResponseParser.call(
      vendor_name: "OpenAI",
      raw_response: {
        "model" => "gpt-4",
        "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5 }
      }
    )

    assert_equal "openai", result["vendor_name"]
  end

  test "handles symbol keys via with_indifferent_access" do
    result = VendorResponseParser.call(
      vendor_name: "openai",
      raw_response: {
        model: "gpt-4",
        usage: { prompt_tokens: 42, completion_tokens: 7 }
      }
    )

    assert_equal "gpt-4", result["ai_model_name"]
    assert_equal 42, result["input_tokens"]
    assert_equal 7, result["output_tokens"]
  end
end
