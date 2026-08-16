require "test_helper"

class SettingTest < ActiveSupport::TestCase
  setup do
    Setting.current.update!(
      instance_name: nil, instance_domain: nil,
      smtp_host: nil, smtp_port: 587, smtp_username: nil, smtp_password: nil,
      ai_provider_name: "NONE", ai_provider_url: nil, ai_provider_api_key: nil
    )
  end

  test ".current returns the singleton row" do
    setting = Setting.current
    assert_equal 1, setting.id
  end

  test ".current creates the row if missing" do
    Setting.delete_all
    assert_equal 0, Setting.count

    setting = Setting.current
    assert_equal 1, setting.id
    assert_equal 1, Setting.count
  end

  test ".get returns DB value when set" do
    Setting.current.update!(instance_name: "My Stray")
    assert_equal "My Stray", Setting.get(:instance_name)
  end

  test ".get falls back to env when DB value is nil" do
    with_env("STRAY_INSTANCE_NAME" => "Env Stray") do
      assert_equal "Env Stray", Setting.get(:instance_name)
    end
  end

  test ".get falls back to YAML default when DB and env are nil" do
    assert_equal "Stray", Setting.get(:instance_name)
  end

  test ".get with unknown key raises ArgumentError" do
    assert_raises(ArgumentError) { Setting.get(:nonexistent) }
  end

  test ".set updates the DB column" do
    Setting.set(:instance_name, "Updated Name")
    assert_equal "Updated Name", Setting.current.instance_name
  end

  test ".set with smtp_port converts to integer" do
    Setting.set(:smtp_port, "2525")
    assert_equal 2525, Setting.current.smtp_port
  end

  test ".set with unknown key raises ArgumentError" do
    assert_raises(ArgumentError) { Setting.set(:nonexistent, "value") }
  end

  test "validates ai_provider_name inclusion" do
    setting = Setting.current
    setting.ai_provider_name = "INVALID"
    assert_not setting.valid?
    assert setting.errors[:ai_provider_name].any?
  end

  test "validates SMTP completeness" do
    setting = Setting.current
    setting.smtp_host = "smtp.example.com"
    setting.smtp_username = nil
    setting.smtp_password = nil
    assert_not setting.valid?
    assert setting.errors[:smtp_host].any?
  end

  test "SMTP completeness passes when all fields present" do
    setting = Setting.current
    setting.smtp_host = "smtp.example.com"
    setting.smtp_port = 587
    setting.smtp_username = "user"
    setting.smtp_password = "pass"
    assert setting.valid?
  end

  test "smtp_password is encrypted at rest" do
    Setting.current.update!(smtp_password: "secret123")
    raw = Setting.connection.execute("SELECT smtp_password FROM settings WHERE id = 1").first["smtp_password"]
    assert_not_equal "secret123", raw
    assert_equal "secret123", Setting.current.smtp_password
  end

  test "ai_provider_api_key is encrypted at rest" do
    Setting.current.update!(ai_provider_api_key: "sk-abc123")
    raw = Setting.connection.execute("SELECT ai_provider_api_key FROM settings WHERE id = 1").first["ai_provider_api_key"]
    assert_not_equal "sk-abc123", raw
    assert_equal "sk-abc123", Setting.current.ai_provider_api_key
  end

  test "get returns zero_shot_threshold from DB" do
    Setting.current.update!(zero_shot_threshold: 0.42)
    assert_equal 0.42, Setting.get(:zero_shot_threshold)
  end

  test "get returns llm_tagging_enabled from DB" do
    Setting.current.update!(llm_tagging_enabled: true)
    assert_equal true, Setting.get(:llm_tagging_enabled)
  end

  test "set updates zero_shot_threshold" do
    Setting.set(:zero_shot_threshold, 0.5)
    assert_equal 0.5, Setting.current.zero_shot_threshold
  end

  test "get returns embedding_model from env" do
    Setting.current.update!(embedding_model: nil)
    with_env("STRAY_EMBEDDING__MODEL" => "custom-embed") do
      assert_equal "custom-embed", Setting.get(:embedding_model)
    end
  end

  private

  def with_env(vars)
    old = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end
