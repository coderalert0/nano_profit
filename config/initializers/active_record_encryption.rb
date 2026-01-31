Rails.application.config.active_record.encryption.primary_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY", "test-primary-key-for-dev-only00")
Rails.application.config.active_record.encryption.deterministic_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY", "test-deterministic-key-dev-only0")
Rails.application.config.active_record.encryption.key_derivation_salt = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT", "test-key-derivation-salt-dev0000")
Rails.application.config.active_record.encryption.support_unencrypted_data = true

if Rails.env.production?
  %w[ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT].each do |key|
    if ENV[key].blank? || ENV[key].include?("dev-only") || ENV[key].include?("dev0000")
      raise "FATAL: #{key} must be set to a secure value in production"
    end
  end
end
