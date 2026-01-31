class CostEntry < ApplicationRecord
  belongs_to :event

  validates :vendor_name, presence: true
  validates :amount_in_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
