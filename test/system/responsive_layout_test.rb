require "test_helper"
require "application_system_test_case"

class ResponsiveLayoutTest < ApplicationSystemTestCase
  test "html has lang attribute" do
    visit about_path

    assert_equal "en", find("html")[:lang]
  end

  test "body has overflow-x hidden to prevent horizontal scroll" do
    visit about_path

    assert_includes find("body")[:class], "overflow-x-hidden"
  end

  test "footer is not fixed so it does not overlap content" do
    visit new_session_path

    footer = find("footer")
    footer_classes = footer[:class]

    refute_includes footer_classes, "fixed", "footer should not be fixed"
  end

  test "layout uses min-h-screen wrapper so footer sits at bottom on short pages" do
    visit about_path

    # The body's main content wrapper should have min-h-screen to push footer down
    wrapper_classes = find("body > div:first-child")[:class]
    assert_includes wrapper_classes, "min-h-screen",
           "content wrapper should have min-h-screen so footer pins to viewport bottom"
  end

  test "inline player stacks media above content on mobile" do
    sign_in_as(users(:one))
    visit root_path

    # Resize to mobile viewport
    resize_to_mobile

    first("[data-player-target='video'] a[data-action*='player#toggle']").click

    assert_selector "[data-player-target='playerBox']:not(.hidden)"

    # On mobile, the player should use flex-col (stacked), not lg:flex-row (side-by-side)
    player = find("[data-player-target='playerBox'] > div")
    assert_equal "column", player.evaluate_script("getComputedStyle(this).flexDirection"),
           "player should stack media/content vertically on mobile"
  end

  test "inline player uses side-by-side layout on desktop" do
    sign_in_as(users(:one))
    visit root_path

    # Desktop viewport (default 1400px)
    resize_to_desktop

    first("[data-player-target='video'] a[data-action*='player#toggle']").click

    assert_selector "[data-player-target='playerBox']:not(.hidden)"

    player = find("[data-player-target='playerBox'] > div")
    assert_equal "row", player.evaluate_script("getComputedStyle(this).flexDirection"),
           "player should use side-by-side layout on desktop"
  end

  test "feed grid shows 6 columns on xl viewport" do
    sign_in_as(users(:one))
    visit root_path

    # XL viewport (1280px+)
    page.driver.browser.manage.window.resize_to(1536, 1024)

    first_item = first("[data-player-target='video']")
    classes = first_item[:class]

    assert_includes classes, "xl:col-span-2",
           "items should use xl:col-span-2 for 6-column density on large monitors"
  end
end
