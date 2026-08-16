require "test_helper"

class ApplicationControllerTest < ActionDispatch::IntegrationTest
  test "non-admin authenticated user is redirected from admin path" do
    user = User.create!(username: "regular", email: "regular@example.com", password: "password", password_confirmation: "password")
    user.update!(admin: false)
    sign_in_as(user)

    get "/admin/settings"
    assert_redirected_to root_path
  end

  test "admin user can access admin path" do
    admin = User.create!(username: "admin", email: "admin2@example.com", password: "password", password_confirmation: "password")
    admin.update!(admin: true)
    sign_in_as(admin)

    get "/admin/settings"
    assert_response :success
  end
end
