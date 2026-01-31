class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  belongs_to :organization, optional: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validate :organization_presence_for_non_admins

  private

  def organization_presence_for_non_admins
    if !admin? && organization_id.blank?
      errors.add(:organization, "is required for non-admin users")
    end
  end
end
