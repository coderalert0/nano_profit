class Customer < ApplicationRecord
  belongs_to :organization
  has_many :usage_telemetry_events, dependent: :destroy
  has_many :margin_alerts, dependent: :destroy

  validates :external_id, presence: true
end
