require "application_system_test_case"

class MobileNavbarTest < ApplicationSystemTestCase
  test "navbar does not contain the paste-link form on mobile" do
    sign_in_as users(:one)
    visit root_path
    resize_to_mobile

    # The paste-link form should NOT be in the navbar
    within "nav" do
      refute_selector "form[action='/links']"
    end
  end

  test "sidebar contains the paste-link form" do
    sign_in_as users(:one)
    visit root_path

    within "aside#sidebar" do
      assert_selector "form[action='/links']"
      assert_selector "input[type='url']"
    end
  end

  test "navbar has account dropdown instead of plain admin and logout links" do
    sign_in_as users(:one)
    visit root_path

    within "nav" do
      # Should have an account dropdown button (data-controller="dropdown")
      assert_selector "div[data-controller='dropdown'] button[aria-label='Account']"
      # Should NOT have a plain "Log out" link visible directly
      refute_selector "a", text: "Log out"
    end
  end
end
