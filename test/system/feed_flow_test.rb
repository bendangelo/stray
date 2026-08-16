require "test_helper"
require "application_system_test_case"

class FeedFlowTest < ApplicationSystemTestCase
  test "view feed shows video grid" do
    sign_in_as(users(:one))
    visit root_path

    assert_text "First Video"
    assert_text "Second Video"
    assert_selector ".grid.grid-cols-12"
    assert_selector "[data-player-target='video']", count: 3
  end

  test "hide an item removes it from grid" do
    sign_in_as(users(:one))
    visit root_path

    assert_text "Second Video"
    within "##{dom_id(items(:video_two))}" do
      click_on "✕ Hide"
    end

    assert_no_text "Second Video"
    assert_text "First Video"
  end

  test "save an item shows saved state" do
    sign_in_as(users(:one))
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      click_on "☆ Save"
    end

    within "##{dom_id(items(:video_one))}" do
      assert_text "★ Saved"
    end
  end

  test "search filters items" do
    sign_in_as(users(:one))
    visit root_path

    fill_in "q", with: "Ruby"
    within "nav form[action='/']" do
      find("button[type='submit']").click
    end

    assert_text "First Video"
    assert_no_text "Second Video"
  end

  test "view sources list" do
    sign_in_as(users(:one))
    visit sources_path

    assert_text "Sources"
    assert_text "Test Channel"
    assert_text "BC Channel"
  end

  test "view source detail page shows grid" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    visit source_path(source)

    assert_text "Test Channel"
    assert_text "First Video"
    assert_selector ".grid.grid-cols-12"
  end

  test "clicking thumbnail opens inline player" do
    sign_in_as(users(:one))
    visit root_path

    first("[data-player-target='video'] a[data-action*='player#toggle']").click

    assert_selector "[data-player-target='playerBox']:not(.hidden)"
    assert_selector "iframe"
  end

  test "closing inline player hides it" do
    sign_in_as(users(:one))
    visit root_path

    first("[data-player-target='video'] a[data-action*='player#toggle']").click
    assert_selector "[data-player-target='playerBox']:not(.hidden)"

    find("[data-action*='player#close']").click
    assert_selector "[data-player-target='playerBox'].hidden", visible: false
  end

  test "clicking a tag filters the feed" do
    sign_in_as(users(:one))
    visit root_path

    assert_text "ruby"
    click_on "ruby"

    assert_text "First Video"
    assert_no_text "Second Video"
  end

  test "sources sidebar shows on feed page" do
    sign_in_as(users(:one))
    visit root_path

    assert_selector "#sidebar"
    within "#sidebar" do
      assert_text "Test Channel", count: 1
    end
  end

  test "sources sidebar shows unseen count badge" do
    sign_in_as(users(:one))
    visit root_path

    within "#sidebar" do
      assert_selector ".bg-carrot-500", minimum: 1
    end
  end
end
