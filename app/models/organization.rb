class Organization < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :margin_alerts, dependent: :destroy
  has_many :vendor_rates, dependent: :destroy

  encrypts :stripe_access_token

  validates :name, presence: true
  validates :api_key, presence: true, uniqueness: true

  before_validation :generate_api_key, on: :create

  def regenerate_api_key!
    update!(api_key: SecureRandom.hex(32))
  end

  private

  def generate_api_key
    self.api_key ||= SecureRandom.hex(32)
  end
end
