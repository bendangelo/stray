require "test_helper"
require "application_system_test_case"

class BareShadeColorsTest < ApplicationSystemTestCase
  test "body renders the champagne background from bg-champagne" do
    visit root_path

    bg = find("body").evaluate_script("getComputedStyle(this).backgroundColor")
    assert_equal "rgb(248, 242, 232)", bg,
      "body should have champagne-500 (#F8F2E8) background once bg-champagne resolves"
  end

  test "bare text-charcoal resolves to charcoal-500 ink" do
    visit about_path

    copy = find("main p", match: :first)
    color = copy.evaluate_script("getComputedStyle(this).color")
    assert_equal "rgb(42, 42, 42)", color,
      "text-charcoal should resolve to #2A2A2A (charcoal-500)"
  end

  test "mobile drawer backdrop is dimmed by bg-charcoal/50" do
    sign_in_as users(:one)
    visit root_path
    resize_to_mobile

    find("button[aria-label='Toggle sources']").click
    assert_selector "aside#sidebar:not(.-translate-x-full)", wait: 5

    backdrop = find("[data-sidebar-target='backdrop']")
    bg = backdrop.evaluate_script("getComputedStyle(this).backgroundColor")
    refute_equal "rgba(0, 0, 0, 0)", bg,
      "backdrop must not be fully transparent — bg-charcoal/50 is currently missing from the build"
  end

  test "flash alert uses cerise danger color" do
    visit new_session_path
    fill_in "email", with: "nope@example.com"
    fill_in "password", with: "wrong"
    click_on "Sign in"

    alert = find("#alert")
    color = alert.evaluate_script("getComputedStyle(this).color")
    assert_equal "rgb(217, 55, 110)", color,
      "flash alert text-cerise should resolve to #D9376E (cerise-500)"
  end
end
