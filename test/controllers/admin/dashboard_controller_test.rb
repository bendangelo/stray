require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(username: "admin", email: "admin@example.com", password: "password", password_confirmation: "password")
    @admin.update!(admin: true)
    @regular = User.create!(username: "regular", email: "regular@example.com", password: "password", password_confirmation: "password")
    @regular.update!(admin: false)
  end

  test "non-authenticated user redirected to login" do
    get admin_path
    assert_redirected_to new_session_path
  end

  test "non-admin user redirected to root" do
    sign_in_as(@regular)
    get admin_path
    assert_redirected_to root_path
  end

  test "admin user can view dashboard" do
    sign_in_as(@admin)
    get admin_path
    assert_response :success
  end

  test "dashboard shows counts and links" do
    sign_in_as(@admin)
    get admin_path
    assert_match "Manage users", response.body
    assert_match "Settings", response.body
    assert_match "Jobs", response.body
  end
end
