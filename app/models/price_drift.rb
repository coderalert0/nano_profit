class PriceDrift < ApplicationRecord
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
      rate = VendorRate.find_by!(
        vendor_name: vendor_name,
        ai_model_name: ai_model_name,
        organization_id: nil
      )
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
