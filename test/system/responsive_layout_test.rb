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
    page.driver.resize(1536, 1024)

    first_item = first("[data-player-target='video']")
    grid_column = first_item.evaluate_script("getComputedStyle(this).gridColumn")

    assert_match /span 2/, grid_column,
           "items should use 2-column spans (6 per row) on xl viewports"
  end

  test "source detail action buttons wrap on narrow screens" do
    sign_in_as(users(:one))
    sources(:youtube).update!(name: "A very long source name that forces the action buttons to wrap")
    visit source_path(sources(:youtube))

    resize_to_mobile

    action_cluster = find("[data-test='source-actions']")

    assert_equal "wrap", action_cluster.evaluate_script("getComputedStyle(this).flexWrap"),
           "source action cluster should have wrap computed style"

    button_tops = action_cluster.all(":scope > *", visible: false).map do |child|
      child.evaluate_script("this.getBoundingClientRect().top")
    end
    assert_operator button_tops.uniq.length, :>, 1,
           "action buttons should wrap to a second row on a narrow viewport"

    action_cluster.all(":scope > *", visible: false).each do |child|
      right = child.evaluate_script("this.getBoundingClientRect().right")
      assert_operator right, :<=, page.evaluate_script("document.documentElement.clientWidth"),
            "action buttons should not overflow the right edge of the viewport"
    end
  end

  test "player box appears in correct grid row on mobile (2 columns)" do
    sign_in_as(users(:one))
    visit root_path

    resize_to_mobile

    # Click the second item (index 1) — in a 2-column grid it should be in row 2
    all("[data-player-target='video'] a[data-action*='player#toggle']")[1].click

    assert_selector "[data-player-target='playerBox']:not(.hidden)"

    # The player box should be in grid row 2 (after the first row of 2 items)
    player_box = find("[data-player-target='playerBox']")
    grid_row = player_box.style("grid-row")["grid-row"]
    assert_equal "2", grid_row,
           "player box should be in row 2 on mobile (2-column grid)"
  end

  test "player box appears in correct grid row on desktop (6 columns)" do
    sign_in_as(users(:one))
    visit root_path

    resize_to_desktop

    # Click the 5th item (index 4) — in a 6-column grid it sits in row 1,
    # so the player box lands in row 2 (below it). The old hardcoded 4-column
    # math would have placed it in row 3.
    all("[data-player-target='video'] a[data-action*='player#toggle']")[4].click

    assert_selector "[data-player-target='playerBox']:not(.hidden)"

    player_box = find("[data-player-target='playerBox']")
    grid_row = player_box.style("grid-row")["grid-row"]
    assert_equal "2", grid_row,
           "player box should be in row 2 on desktop (6-column grid, 5th item)"
  end

  test "tag input form is cloned from template not built by JS" do
    sign_in_as(users(:one))
    visit root_path

    # The template should exist in the DOM (hidden)
    assert_selector "template[data-tag-input-target='template']",
           visible: false, wait: 2

    # Open the actions menu and click "Add tag"
    first("[data-controller='dropdown'] [data-dropdown-target='button']").click
    click_on "Add tag"

    # The form should appear, cloned from the template
    assert_selector "[data-tag-input-target='input']", wait: 5
  end
end
