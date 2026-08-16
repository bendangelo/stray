class SeedSettingsFromEnv < ActiveRecord::Migration[8.1]
  ENV_MAPPING = {
    instance_name:       "STRAY_INSTANCE_NAME",
    instance_domain:     "STRAY_INSTANCE_DOMAIN",
    smtp_host:           "STRAY_SMTP__HOST",
    smtp_port:           "STRAY_SMTP__PORT",
    smtp_username:       "STRAY_SMTP__USERNAME",
    smtp_password:       "STRAY_SMTP__PASSWORD",
    ai_provider_name:    "STRAY_AI_PROVIDER__NAME",
    ai_provider_url:     "STRAY_AI_PROVIDER__URL",
    ai_provider_api_key: "STRAY_AI_PROVIDER__API_KEY"
  }.freeze

  def up
    setting = Setting.find(1)

    updates = {}
    ENV_MAPPING.each do |column, env_key|
      env_value = ENV[env_key]
      next if env_value.blank?

      updates[column] = (column == :smtp_port ? env_value.to_i : env_value)
    end

    setting.update!(updates) if updates.any?
  end

  def down
  end
end
