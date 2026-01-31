class Customer < ApplicationRecord
  belongs_to :organization
  has_many :events, dependent: :destroy
  has_many :stripe_invoices, dependent: :destroy

  before_destroy :cleanup_margin_alerts

  validates :external_id, presence: true, uniqueness: { scope: :organization_id }
  validates :stripe_customer_id, uniqueness: { scope: :organization_id }, allow_nil: true

  private

  def cleanup_margin_alerts
    organization.margin_alerts.where(dimension: "customer", dimension_value: id.to_s).destroy_all
  end
end
