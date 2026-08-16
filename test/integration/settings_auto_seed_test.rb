require "test_helper"

class SettingsAutoSeedTest < ActiveSupport::TestCase
  test "Setting.get reads DB value seeded from env" do
    Setting.current.update!(instance_name: "Seeded From Env")
    assert_equal "Seeded From Env", Setting.get(:instance_name)
  end

  test "DB value overrides env var" do
    ENV["STRAY_INSTANCE_NAME"] = "Env Name"
    Setting.current.update!(instance_name: "DB Name")
    assert_equal "DB Name", Setting.get(:instance_name)
  ensure
    ENV.delete("STRAY_INSTANCE_NAME")
  end

  test "env var used when DB value is nil" do
    Setting.current.update!(instance_name: nil)
    ENV["STRAY_INSTANCE_NAME"] = "Env Fallback"
    assert_equal "Env Fallback", Setting.get(:instance_name)
  ensure
    ENV.delete("STRAY_INSTANCE_NAME")
  end

  test "YAML default used when DB and env are both nil" do
    Setting.current.update!(instance_name: nil)
    assert_equal "Stray", Setting.get(:instance_name)
  end

  test "all settings columns have env mapping" do
    columns = %w[instance_name instance_domain smtp_host smtp_port smtp_username smtp_password ai_provider_name ai_provider_url ai_provider_api_key]
    columns.each do |col|
      assert Setting::ENV_MAPPING.key?(col.to_sym), "missing env mapping for #{col}"
    end
  end
end
