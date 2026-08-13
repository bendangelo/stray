require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "downcases and strips email" do
    user = User.new(email: " DOWNCASED@EXAMPLE.COM ", username: "test", password: "password", password_confirmation: "password")
    assert_equal("downcased@example.com", user.email)
  end

  test "valid user with email, username, and password" do
    user = User.new(email: "test@example.com", username: "test", password: "password", password_confirmation: "password")
    assert user.valid?
  end

  test "invalid with duplicate email" do
    User.create!(email: "dup@example.com", username: "dup1", password: "password", password_confirmation: "password")
    user = User.new(email: "dup@example.com", username: "dup2", password: "password", password_confirmation: "password")
    assert_not user.valid?
  end

  test "invalid without username" do
    user = User.new(email: "nousername@example.com", password: "password", password_confirmation: "password")
    assert_not user.valid?
  end

  test "invalid with short password" do
    user = User.new(email: "short@example.com", username: "short", password: "short", password_confirmation: "short")
    assert_not user.valid?
  end
end
