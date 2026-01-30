module Pricing
  class SyncJob < ApplicationJob
    queue_as :default

    def perform
      result = Pricing::SyncService.new.perform
      Rails.logger.info("Pricing sync complete: #{result.inspect}")
    end
  end
end
