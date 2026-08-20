require "application_system_test_case"

class SourceCollectionMenuTest < ApplicationSystemTestCase
  test "toggle a collection and create one inline" do
    sign_in_as users(:one)
    source = sources(:inactive)
    visit source_path(source)

    click_button "Add to collection"
    within "#source-collections-#{source.id}" do
      click_button "Economics Blogs"
    end
    assert_text "In 1 collection", wait: 5

    within "#source-collections-#{source.id}" do
      fill_in "collection[name]", with: "My New List"
      click_button "+"
    end
    assert_text "In 2 collections", wait: 5
  end
end
