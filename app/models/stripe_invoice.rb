class StripeInvoice < ApplicationRecord
  belongs_to :organization
  belongs_to :customer, optional: true

  validates :stripe_invoice_id, presence: true, uniqueness: true
  validates :stripe_customer_id, presence: true
  validates :amount_in_cents, presence: true
  validates :paid_at, presence: true
  validates :period_start, presence: true
  validates :period_end, presence: true
end
