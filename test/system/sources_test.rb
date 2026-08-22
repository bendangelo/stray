require "test_helper"
require "application_system_test_case"

class SourcesTest < ApplicationSystemTestCase
  test "add source via form" do
    sign_in_as(users(:one))
    visit sources_path

    click_on "+ Add source"
    assert_text "Add source"

    fill_in "Url", with: "https://example.com/feed.xml"
    fill_in "Name", with: "Test RSS Feed"
    select "Rss feed", from: "Kind"
    click_on "Add source"

    assert_text "Test RSS Feed"
  end

  test "edit source name inline" do
    sign_in_as(users(:one))
    visit sources_path

    within "##{dom_id(sources(:youtube))}" do
      find("button[aria-controls^='source-actions-']").click
      click_on "Edit"
    end

    assert_text "Edit source"
    fill_in "Name", with: "Renamed Channel"
    click_on "Save"

    assert_text "Renamed Channel"
  end

  test "pause a source moves it to paused section" do
    sign_in_as(users(:one))
    visit sources_path

    assert_text "Test Channel"

    within "##{dom_id(sources(:youtube))}" do
      find("button[aria-controls^='source-actions-']").click
      click_on "Pause"
    end

    assert_text "Paused"
    within "##{dom_id(sources(:youtube))}" do
      assert_text "Test Channel"
      find("button[aria-controls^='source-actions-']").click
      assert_text "Unpause"
    end
  end

  test "unpause a source moves it back to active section" do
    sign_in_as(users(:one))
    visit sources_path

    within "##{dom_id(sources(:inactive))}" do
      find("button[aria-controls^='source-actions-']").click
      click_on "Unpause"
    end

    assert_no_text "Paused"
  end

  test "delete a source removes it from list" do
    sign_in_as(users(:one))
    visit sources_path

    within "##{dom_id(sources(:bitchute))}" do
      find("button[aria-controls^='source-actions-']").click
      accept_confirm do
        click_on "Delete"
      end
    end

    assert_no_text "BC Channel"
  end

  test "search filters sources by name" do
    sign_in_as(users(:one))
    visit sources_path

    fill_in "Search sources...", with: "Test Channel"
    # Wait for Turbo Frame to update
    within "#sources_list" do
      assert_text "Test Channel"
      assert_no_text "BC Channel"
    end
  end
end
