class UsageTelemetryEvent < ApplicationRecord
  belongs_to :organization
  belongs_to :customer, optional: true
  has_many :cost_entries, dependent: :destroy

  validates :unique_request_token, presence: true, uniqueness: true
  validates :customer_external_id, presence: true
  validates :event_type, presence: true
  validates :revenue_amount_in_cents, presence: true

  scope :processed, -> { where(status: "processed") }
  scope :pending, -> { where(status: "pending") }
  scope :recent, -> { order(occurred_at: :desc) }
end
