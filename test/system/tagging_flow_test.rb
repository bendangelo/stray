require "test_helper"
require "application_system_test_case"

class TaggingFlowTest < ApplicationSystemTestCase
  setup do
    sign_in_as(users(:one))
  end

  test "tag bar shows and filters feed" do
    visit root_path

    within "#tag-bar" do
      assert_text "ruby"
      click_on "ruby"
    end
    assert_text "First Video"
    refute_text "Second Video"
  end

  test "item shows tag chips with provenance" do
    visit root_path
    within first("#item_#{items(:video_one).id}_tags") do
      assert_text "ruby"
    end
  end

  test "tag management page works" do
    visit tags_path
    assert_text "ruby"
    assert_text "rails"
    click_on "New tag"
    fill_in "Name", with: "newtag"
    click_on "Create tag"
    assert_text "newtag"
  end

  test "rename a tag" do
    visit tags_path
    click_on "Rename", match: :first
    fill_in "Name", with: "ruby-renamed"
    click_on "Update tag"
    assert_text "ruby-renamed"
  end
end
