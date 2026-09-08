require "application_system_test_case"

class SidebarBackgroundTest < ApplicationSystemTestCase
  test "sidebar has a distinct background from the body on desktop" do
    sign_in_as users(:one)
    visit root_path
    resize_to_desktop

    sidebar = find("aside#sidebar")
    sidebar_bg = sidebar.evaluate_script("getComputedStyle(this).backgroundColor")
    body_bg = find("body").evaluate_script("getComputedStyle(this).backgroundColor")

    refute_equal body_bg, sidebar_bg,
           "sidebar background should differ from body background for visual separation"
  end

  test "sidebar has an opaque background on mobile" do
    sign_in_as users(:one)
    visit root_path
    resize_to_mobile

    # Open the sidebar
    find("button[aria-label='Toggle sources']").click
    assert_selector "aside#sidebar:not(.-translate-x-full)", wait: 5
    sidebar = find("aside#sidebar")

    bg = sidebar.evaluate_script("getComputedStyle(this).backgroundColor")
    # rgb(250, 247, 242) is champagne-50 — should not be transparent or equal to body
    refute_match /rgba?\(0,\s*0,\s*0,\s*0\)/, bg,
           "sidebar should have an opaque background on mobile, not transparent"
  end
end
