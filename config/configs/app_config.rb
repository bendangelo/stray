# frozen_string_literal: true

# Application-level configuration. Reads DB-first (Setting singleton), falls
# back to STRAY_* environment variables, then YAML defaults in config/stray.yml.
class AppConfig
  ENV_MAPPING = {
    instance_name:      "STRAY_INSTANCE_NAME",
    instance_domain:    "STRAY_INSTANCE_DOMAIN",
    rails_log_level:    "STRAY_RAILS_LOG_LEVEL",
    smtp_host:          "STRAY_SMTP__HOST",
    smtp_port:          "STRAY_SMTP__PORT",
    smtp_username:      "STRAY_SMTP__USERNAME",
    smtp_password:      "STRAY_SMTP__PASSWORD",
    ai_provider_name:   "STRAY_AI_PROVIDER__NAME",
    ai_provider_url:    "STRAY_AI_PROVIDER__URL",
    ai_provider_api_key: "STRAY_AI_PROVIDER__API_KEY"
  }.freeze

  class << self
    def instance_name
      read(:instance_name)
    end

    def instance_domain
      read(:instance_domain)
    end

    def rails_log_level
      read_env(:rails_log_level) || yaml_default(:rails_log_level)
    end

    def smtp
      {
        host: read(:smtp_host),
        port: read(:smtp_port)&.to_i || 587,
        username: read(:smtp_username),
        password: read(:smtp_password)
      }
    end

    def ai_provider
      {
        name: read(:ai_provider_name) || "NONE",
        url: read(:ai_provider_url),
        api_key: read(:ai_provider_api_key)
      }
    end

    def smtp_configured?
      smtp[:host].present?
    end

    private

    def read(key)
      db_value = read_db(key)
      return db_value if db_value.present?

      read_env(key) || yaml_default(key)
    end

    def read_db(key)
      setting = Setting.current
      return nil unless setting

      value = setting.public_send(key)
      value if value.present?
    rescue ActiveRecord::StatementInvalid
      nil
    end

    def read_env(key)
      env_key = ENV_MAPPING[key]
      return nil unless env_key

      ENV[env_key].presence
    end

    def yaml_default(key)
      return nil unless yaml_defaults

      yaml_defaults.dig(Rails.env.to_s, key.to_s)
    end

    def yaml_defaults
      return @yaml_defaults if defined?(@yaml_defaults)

      path = Rails.root.join("config/stray.yml")
      @yaml_defaults = File.exist?(path) ? YAML.safe_load(File.read(path), aliases: true) : nil
    rescue Errno::ENOENT
      @yaml_defaults = nil
    end
  end
end
