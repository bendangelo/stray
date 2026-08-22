require "test_helper"
require "application_system_test_case"

class SearchAutocompleteTest < ApplicationSystemTestCase
  test "typing shows autocomplete dropdown with highlighted results" do
    sign_in_as(users(:one))
    rebuild_full_search_index(Item)
    visit root_path

    fill_in "q", with: "First"

    assert_selector "ul[data-autocomplete-target='results'] li[role='option']", wait: 5
    assert_text "First Video"
    assert_selector "mark", wait: 5
  end

  test "selecting a title navigates to the item" do
    sign_in_as(users(:one))
    rebuild_full_search_index(Item)
    visit root_path

    fill_in "q", with: "First"

    within "ul[data-autocomplete-target='results']" do
      find("li[role='option']", text: "First Video").click
    end

    assert_current_path item_path(items(:video_one))
    assert_text "First Video"
  end

  test "short query does not show dropdown" do
    sign_in_as(users(:one))
    visit root_path

    fill_in "q", with: "Fi"

    assert_no_selector "ul[data-autocomplete-target='results'] li[role='option']", wait: 2
  end
end
