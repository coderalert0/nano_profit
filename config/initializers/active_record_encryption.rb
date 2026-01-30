Rails.application.config.active_record.encryption.primary_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY", "test-primary-key-for-dev-only00")
Rails.application.config.active_record.encryption.deterministic_key = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY", "test-deterministic-key-dev-only0")
Rails.application.config.active_record.encryption.key_derivation_salt = ENV.fetch("ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT", "test-key-derivation-salt-dev0000")
Rails.application.config.active_record.encryption.support_unencrypted_data = true
Rails.application.config.active_record.encryption.extend_queries = true
