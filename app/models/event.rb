class Event < ApplicationRecord
  belongs_to :organization
  belongs_to :customer, optional: true
  has_many :cost_entries, dependent: :destroy

  validates :unique_request_token, presence: true
  validates :customer_external_id, presence: true
  validates :event_type, presence: true
  validates :revenue_amount_in_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: %w[pending customer_linked processed failed] }
  validate :occurred_at_not_too_far_in_future

  scope :processed, -> { where(status: "processed") }
  scope :pending, -> { where(status: "pending") }
  scope :recent, -> { order(occurred_at: :desc) }

  private

  def occurred_at_not_too_far_in_future
    return if occurred_at.nil?
    if occurred_at > 1.hour.from_now
      errors.add(:occurred_at, "cannot be more than 1 hour in the future")
    end
  end
end
