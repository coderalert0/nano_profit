class Customer < ApplicationRecord
  belongs_to :organization
  has_many :usage_telemetry_events, dependent: :destroy
  has_many :margin_alerts, dependent: :destroy

  validates :external_id, presence: true
  validates :stripe_customer_id, uniqueness: { scope: :organization_id }, allow_nil: true
  validates :monthly_subscription_revenue_in_cents, numericality: { greater_than_or_equal_to: 0 }
end
