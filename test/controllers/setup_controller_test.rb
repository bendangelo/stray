require "test_helper"

class SetupControllerTest < ActionDispatch::IntegrationTest
  setup do
    User.delete_all
  end

  test "GET new returns 200 when no users exist" do
    get new_setup_path
    assert_response :success
  end

  test "POST create with valid params creates first user" do
    assert_difference("User.count", 1) do
      post setup_path, params: {
        user: {
          username: "admin",
          email: "admin@example.com",
          password: "password",
          password_confirmation: "password"
        }
      }
    end
    assert_redirected_to new_session_path
  end

  test "POST create when users exist redirects to root" do
    User.create!(username: "existing", email: "existing@example.com", password: "password", password_confirmation: "password")
    post setup_path, params: {
      user: {
        username: "admin",
        email: "admin@example.com",
        password: "password",
        password_confirmation: "password"
      }
    }
    assert_redirected_to root_path
  end

  test "GET new redirects to root when users exist" do
    User.create!(username: "existing", email: "existing@example.com", password: "password", password_confirmation: "password")
    get new_setup_path
    assert_redirected_to root_path
  end

  test "unauthenticated request redirects to setup when no users exist" do
    get root_path
    assert_redirected_to new_setup_path
  end
end
