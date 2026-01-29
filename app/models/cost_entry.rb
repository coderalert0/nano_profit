class CostEntry < ApplicationRecord
  belongs_to :usage_telemetry_event

  validates :vendor_name, presence: true
  validates :amount_in_cents, presence: true
end
