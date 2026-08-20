require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(username: "admin", email: "admin@example.com", password: "password", password_confirmation: "password")
    @admin.update!(admin: true)
    @regular = User.create!(username: "regular", email: "regular@example.com", password: "password", password_confirmation: "password")
    @regular.update!(admin: false)
  end

  test "non-admin user redirected from users index" do
    sign_in_as(@regular)
    get admin_users_path
    assert_redirected_to root_path
  end

  test "admin can list users" do
    sign_in_as(@admin)
    get admin_users_path
    assert_response :success
    assert_match @regular.username, response.body
  end

  test "admin can promote a user to admin" do
    sign_in_as(@admin)
    patch admin_user_path(@regular), params: { user: { admin: true, username: @regular.username, email: @regular.email } }
    assert_redirected_to admin_users_path
    assert @regular.reload.admin?
  end

  test "admin can demote a user" do
    sign_in_as(@admin)
    patch admin_user_path(@regular), params: { user: { admin: false, username: @regular.username, email: @regular.email } }
    assert_redirected_to admin_users_path
    assert_not @regular.reload.admin?
  end

  test "blank password fields preserve existing password" do
    sign_in_as(@admin)
    patch admin_user_path(@regular), params: {
      user: { username: @regular.username, email: @regular.email, password: "", password_confirmation: "" }
    }
    assert_redirected_to admin_users_path
    assert User.authenticate_by(email: @regular.email, password: "password")
  end

  test "admin can reset a user's password" do
    sign_in_as(@admin)
    patch admin_user_path(@regular), params: {
      user: { username: @regular.username, email: @regular.email, password: "newpass123", password_confirmation: "newpass123" }
    }
    assert_redirected_to admin_users_path
    assert User.authenticate_by(email: @regular.email, password: "newpass123")
  end

  test "admin cannot delete their own account" do
    sign_in_as(@admin)
    assert_no_difference("User.count") do
      delete admin_user_path(@admin)
    end
    assert_redirected_to admin_users_path
    follow_redirect!
    assert_match "cannot delete", response.body
  end

  test "admin can delete another user" do
    sign_in_as(@admin)
    assert_difference("User.count", -1) do
      delete admin_user_path(@regular)
    end
    assert_redirected_to admin_users_path
  end

  test "invalid update re-renders edit" do
    sign_in_as(@admin)
    patch admin_user_path(@regular), params: { user: { username: "", email: @regular.email } }
    assert_response :unprocessable_entity
  end
end
