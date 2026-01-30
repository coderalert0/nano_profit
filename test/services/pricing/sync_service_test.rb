require "test_helper"

class Pricing::SyncServiceTest < ActiveSupport::TestCase
  SAMPLE_DATA = {
    "gpt-4o" => {
      "input_cost_per_token" => 0.0000025,
      "output_cost_per_token" => 0.00001,
      "litellm_provider" => "openai"
    },
    "gpt-4o-mini" => {
      "input_cost_per_token" => 0.00000015,
      "output_cost_per_token" => 0.0000006,
      "litellm_provider" => "openai"
    },
    "claude-3-opus-20240229" => {
      "input_cost_per_token" => 0.000015,
      "output_cost_per_token" => 0.000075,
      "litellm_provider" => "anthropic"
    },
    "gemini/gemini-pro" => {
      "input_cost_per_character" => 0.0000003125,
      "output_cost_per_character" => 0.000000625,
      "litellm_provider" => "gemini"
    },
    "groq/llama-3" => {
      "input_cost_per_token" => 0.00000005,
      "output_cost_per_token" => 0.00000008,
      "litellm_provider" => "groq"
    },
    "azure/gpt-4o" => {
      "input_cost_per_token" => 0.0000025,
      "output_cost_per_token" => 0.00001,
      "litellm_provider" => "azure"
    },
    "bedrock/claude-3" => {
      "input_cost_per_token" => 0.000015,
      "output_cost_per_token" => 0.000075,
      "litellm_provider" => "bedrock"
    },
    "mistral-large-latest" => {
      "input_cost_per_token" => 0.000008,
      "output_cost_per_token" => 0.000024,
      "litellm_provider" => "mistral"
    },
    "gpt-3.5-turbo-deprecated" => {
      "input_cost_per_token" => 0.000001,
      "output_cost_per_token" => 0.000002,
      "litellm_provider" => "openai",
      "deprecation_date" => "2024-01-01"
    },
    "o1-no-cost" => {
      "max_tokens" => 4096,
      "litellm_provider" => "openai"
    }
  }.freeze

  setup do
    @service = Pricing::SyncService.new(pricing_data: SAMPLE_DATA)
  end

  test "creates new VendorRate for unknown models" do
    result = @service.perform

    rate = VendorRate.find_by(vendor_name: "openai", ai_model_name: "gpt-4o", organization_id: nil)
    assert_not_nil rate
    assert_equal "0.25".to_d, rate.input_rate_per_1k
    assert_equal "1.0".to_d, rate.output_rate_per_1k
    assert rate.active?
    assert_equal "tokens", rate.unit_type

    assert result[:created] > 0
  end

  test "creates PriceDrift when rate changes and does NOT update VendorRate" do
    VendorRate.create!(
      vendor_name: "openai",
      ai_model_name: "gpt-4o",
      input_rate_per_1k: "1.000000".to_d,
      output_rate_per_1k: "2.000000".to_d,
      unit_type: "tokens",
      active: true,
      organization_id: nil
    )

    assert_difference "PriceDrift.count", 1 do
      @service.perform
    end

    rate = VendorRate.find_by(vendor_name: "openai", ai_model_name: "gpt-4o", organization_id: nil)
    assert_equal "1.0".to_d, rate.input_rate_per_1k

    drift = PriceDrift.find_by(vendor_name: "openai", ai_model_name: "gpt-4o")
    assert_equal "openai", drift.vendor_name
    assert_equal "gpt-4o", drift.ai_model_name
    assert_equal "1.0".to_d, drift.old_input_rate
    assert_equal "0.25".to_d, drift.new_input_rate
    assert drift.pending?
  end

  test "no-op when rates are unchanged" do
    VendorRate.create!(
      vendor_name: "openai",
      ai_model_name: "gpt-4o",
      input_rate_per_1k: "0.25".to_d,
      output_rate_per_1k: "1.0".to_d,
      unit_type: "tokens",
      active: true,
      organization_id: nil
    )

    assert_no_difference "PriceDrift.count" do
      result = @service.perform
      assert result[:unchanged] >= 1
    end
  end

  test "skips deprecated models" do
    @service.perform
    rate = VendorRate.find_by(vendor_name: "openai", ai_model_name: "gpt-3.5-turbo-deprecated")
    assert_nil rate
  end

  test "handles character-based pricing for gemini" do
    @service.perform

    rate = VendorRate.find_by(vendor_name: "gemini", ai_model_name: "gemini-pro", organization_id: nil)
    assert_not_nil rate
    assert_equal "0.125".to_d, rate.input_rate_per_1k
    assert_equal "0.25".to_d, rate.output_rate_per_1k
  end

  test "creates rates for groq provider" do
    @service.perform

    rate = VendorRate.find_by(vendor_name: "groq", ai_model_name: "llama-3", organization_id: nil)
    assert_not_nil rate
    assert rate.active?
  end

  test "creates rates for azure provider" do
    @service.perform

    rate = VendorRate.find_by(vendor_name: "azure", ai_model_name: "gpt-4o", organization_id: nil)
    assert_not_nil rate
    assert rate.active?
  end

  test "creates rates for bedrock provider" do
    @service.perform

    rate = VendorRate.find_by(vendor_name: "bedrock", ai_model_name: "claude-3", organization_id: nil)
    assert_not_nil rate
    assert rate.active?
  end

  test "skips entries with no cost data" do
    result = @service.perform

    rate = VendorRate.find_by(vendor_name: "openai", ai_model_name: "o1-no-cost")
    assert_nil rate
    assert result[:skipped] >= 1
  end

  test "skips unsupported vendors" do
    @service.perform
    rate = VendorRate.find_by(vendor_name: "mistral", ai_model_name: "mistral-large-latest")
    assert_nil rate
  end

  test "never touches org-specific rates" do
    org_rate = vendor_rates(:openai_gpt4_acme)
    original_input = org_rate.input_rate_per_1k

    @service.perform

    assert_equal original_input, org_rate.reload.input_rate_per_1k
  end

  test "uses percentage-based drift threshold" do
    VendorRate.create!(
      vendor_name: "openai",
      ai_model_name: "gpt-4o",
      input_rate_per_1k: "0.2525".to_d,   # 1% above 0.25
      output_rate_per_1k: "1.0".to_d,
      unit_type: "tokens",
      active: true,
      organization_id: nil
    )

    # Default threshold is 1% (0.01). 0.2525 vs 0.25 = 0.99% change — below threshold
    assert_no_difference "PriceDrift.count" do
      @service.perform
    end

    # Set a tighter threshold — now the same difference triggers a drift
    PlatformSetting.drift_threshold = "0.005"  # 0.5%
    service2 = Pricing::SyncService.new(pricing_data: SAMPLE_DATA)

    assert_difference "PriceDrift.count", 1 do
      service2.perform
    end
  end

  test "idempotent — second run with same data creates no new records" do
    @service.perform

    vendor_count_before = VendorRate.count
    drift_count_before = PriceDrift.count

    @service.perform

    assert_equal vendor_count_before, VendorRate.count
    assert_equal drift_count_before, PriceDrift.count
  end

  test "deactivates global rates not present in upstream data" do
    # Create a rate that won't appear in SAMPLE_DATA
    stale_rate = VendorRate.create!(
      vendor_name: "openai",
      ai_model_name: "davinci-002",
      input_rate_per_1k: "1.0".to_d,
      output_rate_per_1k: "2.0".to_d,
      unit_type: "tokens",
      active: true,
      organization_id: nil
    )

    result = @service.perform

    assert_not stale_rate.reload.active?, "Stale rate should be deactivated"
    assert result[:deactivated] >= 1
  end

  test "does not deactivate org-specific rates" do
    org_rate = vendor_rates(:openai_gpt4_acme)
    assert org_rate.active?

    @service.perform

    assert org_rate.reload.active?, "Org-specific rate should not be deactivated"
  end

  test "updates existing pending drift with new rates instead of creating duplicate" do
    VendorRate.create!(
      vendor_name: "openai",
      ai_model_name: "gpt-4o",
      input_rate_per_1k: "1.000000".to_d,
      output_rate_per_1k: "2.000000".to_d,
      unit_type: "tokens",
      active: true,
      organization_id: nil
    )

    # First sync creates a pending drift
    @service.perform
    drift = PriceDrift.find_by(vendor_name: "openai", ai_model_name: "gpt-4o", status: :pending)
    assert_not_nil drift
    assert_equal "0.25".to_d, drift.new_input_rate

    # Second sync with different upstream data updates the existing drift
    updated_data = SAMPLE_DATA.dup
    updated_data["gpt-4o"] = {
      "input_cost_per_token" => 0.000003,
      "output_cost_per_token" => 0.000012,
      "litellm_provider" => "openai"
    }
    service2 = Pricing::SyncService.new(pricing_data: updated_data)

    assert_no_difference "PriceDrift.count" do
      service2.perform
    end

    drift.reload
    assert_equal "0.3".to_d, drift.new_input_rate
    assert_equal "1.2".to_d, drift.new_output_rate
  end
end
