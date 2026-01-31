class Event < ApplicationRecord
  belongs_to :organization
  belongs_to :customer, optional: true
  has_many :cost_entries, dependent: :destroy

  validates :unique_request_token, presence: true
  validates :customer_external_id, presence: true
  validates :event_type, presence: true
  validates :revenue_amount_in_cents, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100_000_00 }
  validates :status, inclusion: { in: %w[pending customer_linked processed failed] }
  validate :occurred_at_within_bounds

  scope :processed, -> { where(status: "processed") }
  scope :pending, -> { where(status: "pending") }
  scope :recent, -> { order(occurred_at: :desc) }

  private

  def occurred_at_within_bounds
    return if occurred_at.nil?
    if occurred_at > 1.hour.from_now
      errors.add(:occurred_at, "cannot be more than 1 hour in the future")
    end
    if occurred_at < 90.days.ago
      errors.add(:occurred_at, "cannot be more than 90 days in the past")
    end
  end
end
