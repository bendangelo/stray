require "test_helper"
require "application_system_test_case"

class ItemShowTest < ApplicationSystemTestCase
  test "show page for a video item renders embed and download command" do
    sign_in_as(users(:one))
    item = items(:video_one)
    visit item_path(item)

    assert_text "First Video"
    assert_selector "iframe"
    assert_text "yt-dlp"
    assert_button "Copy"
  end

  test "copy button copies the yt-dlp command to the clipboard" do
    sign_in_as(users(:one))
    item = items(:video_one)
    visit item_path(item)

    # stub navigator.clipboard.readText so we can assert what was written
    page.execute_script <<-JS
      window.__copied = null;
      navigator.clipboard.writeText = function(text) {
        window.__copied = text;
        return Promise.resolve();
      };
    JS

    click_on "Copy"

    copied = page.evaluate_script("window.__copied")
    assert_equal %(yt-dlp -f "bv*+ba/b" "#{item.url}"), copied
  end

  test "copy button shows Copied! state" do
    sign_in_as(users(:one))
    item = items(:video_one)
    visit item_path(item)

    page.execute_script <<-JS
      navigator.clipboard.writeText = function(text) { return Promise.resolve(); };
    JS

    click_on "Copy"
    assert_text "Copied!", wait: 2
  end

  test "prev/next navigation moves between items in feed order" do
    sign_in_as(users(:one))
    # video_two is 1.day.ago; in feed order (weight 1.0) it sits between
    # video_four (6h ago) and video_one (2d ago)
    visit item_path(items(:video_two), from: "feed")

    # Next should be the older item (video_one, 2d ago)
    find("nav a", text: "Next").click
    # On the next page, the title should be video_one's title
    assert_text "First Video", wait: 3
  end

  test "back to feed link returns to root from feed context" do
    sign_in_as(users(:one))
    visit item_path(items(:video_one), from: "feed")

    click_on "← Back"
    assert_current_path root_path
  end

  test "back to source link returns to the source page" do
    sign_in_as(users(:one))
    item = items(:video_one)
    visit item_path(item, from: "source", source_id: item.source_id)

    click_on "← Back"
    assert_current_path source_path(item.source)
  end

  test "actions menu Open details navigates to the show page" do
    sign_in_as(users(:one))
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      find("button[aria-controls^='item-actions-']").click
      click_on "Open details"
    end

    assert_text "First Video"
    assert_selector "iframe"
  end

  test "inline player Open details page link navigates to the show page" do
    sign_in_as(users(:one))
    visit root_path

    first("[data-player-target='video'] a[data-action*='player#toggle']").click
    assert_selector "[data-player-target='playerBox']:not(.hidden)"

    click_on "Open details page"
    assert_text "Third Video"
    assert_selector "iframe"
  end

  test "inline player shows download command for video items" do
    sign_in_as(users(:one))
    visit root_path

    first("[data-player-target='video'] a[data-action*='player#toggle']").click
    assert_selector "[data-player-target='playerBox']:not(.hidden)"

    assert_text "yt-dlp"
    assert_button "Copy"
  end

  test "show page displays tags with provenance icons" do
    sign_in_as(users(:one))
    visit item_path(items(:video_one))

    assert_text "TAGS"
    assert_text "ruby"
    assert_text "rails"
    # provenance icons are wrapped in a span with a title attribute
    assert_selector "span[title='Tagged by embedding similarity']", minimum: 1
  end

  test "show page displays ranking explanation" do
    sign_in_as(users(:one))
    visit item_path(items(:video_one))

    assert_text "WHY IS THIS HERE?"
    assert_text "Weight"
  end

  test "inline player shows a star toggle button next to the title" do
    sign_in_as(users(:one))
    item = items(:video_three)
    assert item.unseen?

    visit root_path
    first("[data-player-target='video'] a[data-action*='player#toggle']").click
    assert_selector "[data-player-target='playerBox']:not(.hidden)"

    within "#item_star_#{item.id}" do
      assert_selector "a[aria-label='Star']"
      assert_selector "a[aria-pressed='false']"
    end
  end

  test "clicking the player star toggle saves the item and flips to filled" do
    sign_in_as(users(:one))
    item = items(:video_three)
    assert item.unseen?

    visit root_path
    first("[data-action*='player#toggle']").click
    assert_selector "[data-player-target='playerBox']:not(.hidden)"

    within "#item_star_#{item.id}" do
      find("a[aria-label='Star']").click
      assert_selector "a[aria-label='Unstar']", wait: 3
      assert_selector "a[aria-pressed='true']"
    end
    assert item.reload.saved?
  end
end
