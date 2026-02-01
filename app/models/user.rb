class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  belongs_to :organization, optional: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true

  def email_verified?
    email_verified_at.present?
  end

  def generate_email_verification_token!
    update!(email_verification_token: SecureRandom.urlsafe_base64(32))
  end

  def verify_email!
    update!(email_verified_at: Time.current, email_verification_token: nil)
  end
end
