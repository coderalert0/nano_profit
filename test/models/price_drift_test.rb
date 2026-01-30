require "test_helper"

class PriceDriftTest < ActiveSupport::TestCase
  test "valid price drift" do
    drift = PriceDrift.new(
      vendor_name: "openai",
      ai_model_name: "gpt-4o",
      old_input_rate: 2.5,
      new_input_rate: 3.0,
      old_output_rate: 10.0,
      new_output_rate: 12.0
    )
    assert drift.valid?
  end

  test "requires vendor_name" do
    drift = PriceDrift.new(ai_model_name: "gpt-4", old_input_rate: 1, new_input_rate: 2, old_output_rate: 1, new_output_rate: 2)
    assert_not drift.valid?
    assert_includes drift.errors[:vendor_name], "can't be blank"
  end

  test "requires ai_model_name" do
    drift = PriceDrift.new(vendor_name: "openai", old_input_rate: 1, new_input_rate: 2, old_output_rate: 1, new_output_rate: 2)
    assert_not drift.valid?
    assert_includes drift.errors[:ai_model_name], "can't be blank"
  end

  test "requires all rate fields" do
    drift = PriceDrift.new(vendor_name: "openai", ai_model_name: "gpt-4")
    assert_not drift.valid?
    assert_includes drift.errors[:old_input_rate], "can't be blank"
    assert_includes drift.errors[:new_input_rate], "can't be blank"
    assert_includes drift.errors[:old_output_rate], "can't be blank"
    assert_includes drift.errors[:new_output_rate], "can't be blank"
  end

  test "defaults to pending status" do
    drift = PriceDrift.new
    assert_equal "pending", drift.status
  end

  test "input_drift_pct calculates percentage change" do
    drift = price_drifts(:pending_drift)
    # old: 3.0, new: 3.5 → (3.5 - 3.0) / 3.0 * 100 = 16.666...
    expected = (BigDecimal("3.5") - BigDecimal("3.0")) / BigDecimal("3.0") * 100
    assert_equal expected.round(4), drift.input_drift_pct.round(4)
  end

  test "output_drift_pct calculates percentage change" do
    drift = price_drifts(:pending_drift)
    # old: 6.0, new: 7.0 → (7.0 - 6.0) / 6.0 * 100 = 16.666...
    expected = (BigDecimal("7.0") - BigDecimal("6.0")) / BigDecimal("6.0") * 100
    assert_equal expected.round(4), drift.output_drift_pct.round(4)
  end

  test "input_drift_pct returns zero when old rate is zero" do
    drift = PriceDrift.new(old_input_rate: 0, new_input_rate: 1.0, old_output_rate: 1.0, new_output_rate: 1.0, vendor_name: "x", ai_model_name: "y")
    assert_equal BigDecimal("0"), drift.input_drift_pct
  end

  test "output_drift_pct returns zero when old rate is zero" do
    drift = PriceDrift.new(old_input_rate: 1.0, new_input_rate: 1.0, old_output_rate: 0, new_output_rate: 1.0, vendor_name: "x", ai_model_name: "y")
    assert_equal BigDecimal("0"), drift.output_drift_pct
  end

  test "apply! updates VendorRate and sets status to applied" do
    drift = price_drifts(:pending_drift)
    rate = vendor_rates(:openai_gpt4_global)

    assert_equal "pending", drift.status

    drift.apply!

    drift.reload
    rate.reload

    assert_equal "applied", drift.status
    assert_equal drift.new_input_rate, rate.input_rate_per_1k
    assert_equal drift.new_output_rate, rate.output_rate_per_1k
  end

  test "ignore! sets status to ignored" do
    drift = price_drifts(:pending_drift)
    assert_equal "pending", drift.status

    drift.ignore!

    assert_equal "ignored", drift.reload.status
  end

  test "pending scope returns only pending drifts" do
    assert PriceDrift.pending.all?(&:pending?)
  end
end
