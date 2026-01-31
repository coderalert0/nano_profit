class VendorRate < ApplicationRecord
  belongs_to :organization, optional: true

  validates :vendor_name, presence: true
  validates :ai_model_name, presence: true
  validates :input_rate_per_1k, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :output_rate_per_1k, presence: true, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(active: true) }

  def self.find_rate(vendor_name:, ai_model_name:, organization: nil)
    if organization
      rate = active.find_by(vendor_name: vendor_name, ai_model_name: ai_model_name, organization: organization)
      return rate if rate
    end

    active.find_by(vendor_name: vendor_name, ai_model_name: ai_model_name, organization_id: nil)
  end

  def self.find_rate_for_processing(vendor_name:, ai_model_name:, organization: nil)
    if organization
      rate = find_by(vendor_name: vendor_name, ai_model_name: ai_model_name, organization: organization)
      return rate if rate
    end

    find_by(vendor_name: vendor_name, ai_model_name: ai_model_name, organization_id: nil)
  end
end
