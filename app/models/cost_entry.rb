class CostEntry < ApplicationRecord
  belongs_to :event

  validates :vendor_name, presence: true
  validates :amount_in_cents, presence: true
end
