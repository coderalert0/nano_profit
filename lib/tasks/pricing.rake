namespace :pricing do
  desc "Sync global vendor rates from LiteLLM pricing data"
  task sync_global: :environment do
    result = Pricing::SyncService.new.perform
    puts "Pricing sync complete: #{result.inspect}"
  end
end
