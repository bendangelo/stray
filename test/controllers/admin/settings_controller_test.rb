require "test_helper"

class Admin::SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(username: "admin", email: "admin@example.com", password: "password", password_confirmation: "password")
    @admin.update!(admin: true)
    @regular = User.create!(username: "regular", email: "regular@example.com", password: "password", password_confirmation: "password")
    @regular.update!(admin: false)
  end

  test "non-authenticated user redirected to login" do
    get admin_settings_path
    assert_redirected_to new_session_path
  end

  test "non-admin user redirected to root" do
    sign_in_as(@regular)
    get admin_settings_path
    assert_redirected_to root_path
  end

  test "admin user can view settings" do
    sign_in_as(@admin)
    get admin_settings_path
    assert_response :success
  end

  test "admin can update settings with valid params" do
    sign_in_as(@admin)
    patch admin_settings_path, params: { setting: { instance_name: "My Stray", instance_domain: "stray.example.com" } }
    assert_redirected_to admin_settings_path
    assert_equal "My Stray", Setting.current.instance_name
    follow_redirect!
    assert_match "Settings updated", response.body
  end

  test "admin update with invalid ai_provider_name re-renders" do
    sign_in_as(@admin)
    patch admin_settings_path, params: { setting: { ai_provider_name: "INVALID" } }
    assert_response :unprocessable_entity
  end

  test "blank password fields preserve existing value" do
    sign_in_as(@admin)
    Setting.current.update!(smtp_password: "existingpass")
    patch admin_settings_path, params: { setting: { smtp_host: "smtp.new.com", smtp_password: "" } }
    Setting.current.reload
    assert_equal "smtp.new.com", Setting.current.smtp_host
    assert_equal "existingpass", Setting.current.smtp_password
  end
end
