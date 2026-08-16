require "test_helper"

class AppConfigTest < ActiveSupport::TestCase
  setup do
    Setting.current.update!(
      instance_name: nil, instance_domain: nil,
      smtp_host: nil, smtp_port: 587, smtp_username: nil, smtp_password: nil,
      ai_provider_name: nil, ai_provider_url: nil, ai_provider_api_key: nil
    )
  end

  test "instance_name reads from DB when set" do
    Setting.current.update!(instance_name: "DB Stray")
    assert_equal "DB Stray", AppConfig.instance_name
  end

  test "instance_name falls back to env when DB is nil" do
    ENV["STRAY_INSTANCE_NAME"] = "Env Stray"
    assert_equal "Env Stray", AppConfig.instance_name
  ensure
    ENV.delete("STRAY_INSTANCE_NAME")
  end

  test "instance_name falls back to YAML default when DB and env are nil" do
    assert_equal "Stray", AppConfig.instance_name
  end

  test "instance_domain reads from DB when set" do
    Setting.current.update!(instance_domain: "db.example.com")
    assert_equal "db.example.com", AppConfig.instance_domain
  end

  test "smtp returns hash with DB values" do
    Setting.current.update!(smtp_host: "smtp.db.com", smtp_port: 2525, smtp_username: "dbuser", smtp_password: "dbpass")
    smtp = AppConfig.smtp
    assert_equal "smtp.db.com", smtp[:host]
    assert_equal 2525, smtp[:port]
    assert_equal "dbuser", smtp[:username]
    assert_equal "dbpass", smtp[:password]
  end

  test "smtp falls back to env values" do
    Setting.current.update!(smtp_host: nil, smtp_port: nil, smtp_username: nil, smtp_password: nil)
    ENV["STRAY_SMTP__HOST"] = "smtp.env.com"
    ENV["STRAY_SMTP__PORT"] = "465"
    ENV["STRAY_SMTP__USERNAME"] = "envuser"
    ENV["STRAY_SMTP__PASSWORD"] = "envpass"
    smtp = AppConfig.smtp
    assert_equal "smtp.env.com", smtp[:host]
    assert_equal 465, smtp[:port]
    assert_equal "envuser", smtp[:username]
    assert_equal "envpass", smtp[:password]
  ensure
    %w[STRAY_SMTP__HOST STRAY_SMTP__PORT STRAY_SMTP__USERNAME STRAY_SMTP__PASSWORD].each { |k| ENV.delete(k) }
  end

  test "smtp_configured? is false without host" do
    refute AppConfig.smtp_configured?
  end

  test "smtp_configured? is true when DB host is set" do
    Setting.current.update!(smtp_host: "smtp.example.com", smtp_port: 587, smtp_username: "user", smtp_password: "pass")
    assert AppConfig.smtp_configured?
  end

  test "smtp_configured? is true when env host is set" do
    ENV["STRAY_SMTP__HOST"] = "smtp.env.com"
    assert AppConfig.smtp_configured?
  ensure
    ENV.delete("STRAY_SMTP__HOST")
  end

  test "ai_provider returns hash with DB values" do
    Setting.current.update!(ai_provider_name: "OLLAMA", ai_provider_url: "http://ollama:11434")
    provider = AppConfig.ai_provider
    assert_equal "OLLAMA", provider[:name]
    assert_equal "http://ollama:11434", provider[:url]
  end

  test "ai_provider falls back to env" do
    Setting.current.update!(ai_provider_name: nil)
    ENV["STRAY_AI_PROVIDER__NAME"] = "OPENAI_COMPATIBLE"
    provider = AppConfig.ai_provider
    assert_equal "OPENAI_COMPATIBLE", provider[:name]
  ensure
    ENV.delete("STRAY_AI_PROVIDER__NAME")
  end

  test "ai_provider defaults to NONE" do
    Setting.current.update!(ai_provider_name: nil)
    ENV.delete("STRAY_AI_PROVIDER__NAME")
    provider = AppConfig.ai_provider
    assert_equal "NONE", provider[:name]
  end

  test "rails_log_level reads from env (stays env-only)" do
    ENV["STRAY_RAILS_LOG_LEVEL"] = "info"
    assert_equal "info", AppConfig.rails_log_level
  ensure
    ENV.delete("STRAY_RAILS_LOG_LEVEL")
  end

  test "rails_log_level falls back to YAML default in test" do
    assert_equal "warn", AppConfig.rails_log_level
  end
end
