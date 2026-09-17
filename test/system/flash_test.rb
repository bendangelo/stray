require "test_helper"
require "application_system_test_case"

class FlashTest < ApplicationSystemTestCase
  test "flash alert renders cerise border and role" do
    visit new_session_path
    fill_in "email", with: "nope@example.com"
    fill_in "password", with: "wrong"
    click_on "Sign in"

    alert = find("#alert")
    assert_equal "alert", alert["role"]
    assert_includes alert[:class], "border-cerise"
  end

  test "setup page uses the shared flash partial" do
    visit new_setup_path

    # No flash set: partial renders nothing
    refute_selector "#alert"
    refute_selector "#notice"
  end
end
