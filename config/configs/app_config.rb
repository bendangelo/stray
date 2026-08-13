# frozen_string_literal: true

# Application-level configuration, loaded from config/stray.yml (defaults) and
# STRAY_* environment variables. Missing required values raise at boot in
# production so misconfiguration fails fast.
class AppConfig < ApplicationConfig
  config_name :stray

  attr_config :instance_name, :instance_domain, :rails_log_level,
    smtp: { host: nil, port: 587, username: nil, password: nil },
    ai_provider: { name: "NONE", url: nil, api_key: nil }

  required :instance_domain, :rails_log_level, env: :production
  required :instance_name, env: { except: %i[development test] }

  on_load :validate_smtp

  def smtp_configured?
    smtp["host"].present?
  end

  private

  def validate_smtp
    return unless smtp["host"].present?

    return if %w[port username password].all? { |key| smtp[key].present? }

    raise_validation_error("STRAY_SMTP__HOST set but STRAY_SMTP__PORT/USERNAME/PASSWORD missing")
  end
end
