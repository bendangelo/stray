if ENV["STRAY_ENCRYPTION_KEY"].present?
  Rails.application.config.active_record.encryption.primary_key = ENV["STRAY_ENCRYPTION_KEY"]
  Rails.application.config.active_record.encryption.deterministic_key = ENV["STRAY_ENCRYPTION_KEY"]
  Rails.application.config.active_record.encryption.key_derivation_salt = ENV["STRAY_ENCRYPTION_KEY"]
elsif Rails.env.local?
  Rails.application.config.active_record.encryption.primary_key = "0000000000000000000000000000000000000000000000000000000000000000"
  Rails.application.config.active_record.encryption.deterministic_key = "0000000000000000000000000000000000000000000000000000000000000000"
  Rails.application.config.active_record.encryption.key_derivation_salt = "0000000000000000000000000000000000000000000000000000000000000000"
end
