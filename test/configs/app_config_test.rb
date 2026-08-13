# frozen_string_literal: true

require "test_helper"
require "anyway/testing/helpers"

class AppConfigTest < ActiveSupport::TestCase
  include Anyway::Testing::Helpers

  test "loads defaults from YAML in test env" do
    config = AppConfig.new

    assert_equal "Stray", config.instance_name
    assert_equal "localhost", config.instance_domain
    assert_equal "warn", config.rails_log_level
  end

  test "smtp_configured? is false without a host" do
    refute AppConfig.new.smtp_configured?
  end

  test "smtp_configured? is true when host is present" do
    with_env(
      "STRAY_SMTP__HOST" => "smtp.example.com",
      "STRAY_SMTP__PORT" => "587",
      "STRAY_SMTP__USERNAME" => "user",
      "STRAY_SMTP__PASSWORD" => "pass"
    ) do
      config = AppConfig.new

      assert config.smtp_configured?
      assert_equal "smtp.example.com", config.smtp["host"]
      assert_equal 587, config.smtp["port"]
    end
  end

  test "raises when SMTP host is set but credentials are missing" do
    with_env("STRAY_SMTP__HOST" => "smtp.example.com") do
      assert_raises(Anyway::Config::ValidationError) { AppConfig.new }
    end
  end
end
