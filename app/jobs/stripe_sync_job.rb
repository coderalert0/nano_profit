class StripeSyncJob < ApplicationJob
  queue_as :default

  def perform(organization_id)
    organization = Organization.find(organization_id)
    return unless organization.stripe_access_token.present?

    Stripe::InvoiceSyncService.new(organization).sync
  end
end
