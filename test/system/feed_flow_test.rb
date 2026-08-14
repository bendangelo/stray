require "test_helper"
require "application_system_test_case"

class FeedFlowTest < ApplicationSystemTestCase
  test "view feed and hide an item" do
    sign_in_as(users(:one))
    visit root_path

    assert_text "Your Feed"
    assert_text "First Video"
    assert_text "Second Video"

    within "##{dom_id(items(:video_two))}" do
      find("button[title='Hide']").click
    end

    assert_no_text "Second Video"
    assert_text "First Video"
  end

  test "save an item and see it highlighted" do
    sign_in_as(users(:one))
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      find("button[title='Save']").click
    end

    assert_selector "##{dom_id(items(:video_one))} svg[fill='currentColor']"
  end

  test "search filters items" do
    sign_in_as(users(:one))
    visit root_path

    fill_in "q", with: "Ruby"
    click_button "Search"

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

  test "view source detail page" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    visit source_path(source)

    assert_text "Test Channel"
    assert_text "First Video"
  end
end
