require "test_helper"

class VendorRateTest < ActiveSupport::TestCase
  test "valid vendor rate" do
    rate = VendorRate.new(
      vendor_name: "openai",
      ai_model_name: "gpt-4o",
      input_rate_per_1k: 2.5,
      output_rate_per_1k: 10.0
    )
    assert rate.valid?
  end

  test "requires vendor_name" do
    rate = VendorRate.new(ai_model_name: "gpt-4", input_rate_per_1k: 1, output_rate_per_1k: 1)
    assert_not rate.valid?
    assert_includes rate.errors[:vendor_name], "can't be blank"
  end

  test "requires ai_model_name" do
    rate = VendorRate.new(vendor_name: "openai", input_rate_per_1k: 1, output_rate_per_1k: 1)
    assert_not rate.valid?
    assert_includes rate.errors[:ai_model_name], "can't be blank"
  end

  test "requires input_rate_per_1k" do
    rate = VendorRate.new(vendor_name: "openai", ai_model_name: "gpt-4", output_rate_per_1k: 1)
    assert_not rate.valid?
    assert_includes rate.errors[:input_rate_per_1k], "can't be blank"
  end

  test "requires output_rate_per_1k" do
    rate = VendorRate.new(vendor_name: "openai", ai_model_name: "gpt-4", input_rate_per_1k: 1)
    assert_not rate.valid?
    assert_includes rate.errors[:output_rate_per_1k], "can't be blank"
  end

  test "active scope returns only active rates" do
    active_count = VendorRate.active.count
    all_count = VendorRate.count
    assert active_count < all_count, "Should have some inactive rates in fixtures"
    assert VendorRate.active.all? { |r| r.active? }
  end

  test "find_rate returns org-specific rate when available" do
    org = organizations(:acme)
    rate = VendorRate.find_rate(vendor_name: "openai", ai_model_name: "gpt-4", organization: org)
    assert_not_nil rate
    assert_equal org.id, rate.organization_id
    assert_equal BigDecimal("2.5"), rate.input_rate_per_1k
  end

  test "find_rate falls back to global rate when no org rate" do
    org = organizations(:acme)
    rate = VendorRate.find_rate(vendor_name: "anthropic", ai_model_name: "claude-3", organization: org)
    assert_not_nil rate
    assert_nil rate.organization_id
  end

  test "find_rate returns global rate when no org specified" do
    rate = VendorRate.find_rate(vendor_name: "openai", ai_model_name: "gpt-4")
    assert_not_nil rate
    assert_nil rate.organization_id
    assert_equal BigDecimal("3.0"), rate.input_rate_per_1k
  end

  test "find_rate returns nil for unknown vendor/model" do
    rate = VendorRate.find_rate(vendor_name: "unknown", ai_model_name: "unknown")
    assert_nil rate
  end

  test "find_rate ignores inactive rates" do
    rate = VendorRate.find_rate(vendor_name: "openai", ai_model_name: "gpt-3.5")
    assert_nil rate
  end

  test "belongs to organization optionally" do
    rate = vendor_rates(:openai_gpt4_global)
    assert_nil rate.organization

    rate = vendor_rates(:openai_gpt4_acme)
    assert_equal organizations(:acme), rate.organization
  end
end
