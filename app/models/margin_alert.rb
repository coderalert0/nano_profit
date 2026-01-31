class MarginAlert < ApplicationRecord
  belongs_to :organization
  belongs_to :acknowledged_by, class_name: "User", optional: true

  validates :alert_type, presence: true, inclusion: { in: %w[negative_margin below_threshold] }
  validates :message, presence: true
  validates :dimension, inclusion: { in: %w[event_type customer] }
  validates :dimension_value, presence: true

  scope :unacknowledged, -> { where(acknowledged_at: nil) }
  scope :recent, -> { order(created_at: :desc) }

  def acknowledged?
    acknowledged_at.present?
  end

  def acknowledge!(user:, notes: nil)
    update!(acknowledged_at: Time.current, acknowledged_by: user, notes: notes.presence)
  end

  def customer?
    dimension == "customer"
  end

  def event_type?
    dimension == "event_type"
  end

  def linked_customer
    organization.customers.find(dimension_value) if customer?
  end
end
