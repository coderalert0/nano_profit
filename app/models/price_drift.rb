class PriceDrift < ApplicationRecord
  class StaleDriftError < StandardError; end

  enum :status, { pending: 0, applied: 1, ignored: 2 }

  validates :vendor_name, presence: true
  validates :ai_model_name, presence: true
  validates :old_input_rate, presence: true
  validates :new_input_rate, presence: true
  validates :old_output_rate, presence: true
  validates :new_output_rate, presence: true

  def input_drift_pct
    return BigDecimal("0") if old_input_rate.zero?
    (new_input_rate - old_input_rate) / old_input_rate * 100
  end

  def output_drift_pct
    return BigDecimal("0") if old_output_rate.zero?
    (new_output_rate - old_output_rate) / old_output_rate * 100
  end

  def apply!
    transaction do
      rate = VendorRate.lock.find_by!(
        vendor_name: vendor_name,
        ai_model_name: ai_model_name,
        organization_id: nil
      )

      if rate.input_rate_per_1k != old_input_rate || rate.output_rate_per_1k != old_output_rate
        raise StaleDriftError, "Rate has changed since drift was detected. " \
          "Expected input=#{old_input_rate}, output=#{old_output_rate}; " \
          "got input=#{rate.input_rate_per_1k}, output=#{rate.output_rate_per_1k}"
      end

      rate.update!(
        input_rate_per_1k: new_input_rate,
        output_rate_per_1k: new_output_rate
      )
      applied!
    end
  end

  def ignore!
    ignored!
  end
end
