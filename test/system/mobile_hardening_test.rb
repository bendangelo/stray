require "test_helper"
require "application_system_test_case"

class MobileHardeningTest < ApplicationSystemTestCase
  test "sidebar rows are at least 44px tall on mobile" do
    sign_in_as users(:one)
    visit root_path
    resize_to_mobile

    find("button[aria-label='Toggle sources']").click
    row = first("#sidebar .flex.items-center.gap-1")
    height = row.evaluate_script("this.getBoundingClientRect().height")
    assert_operator height, :>=, 44, "sidebar source row got #{height}"
  end

  test "closing the drawer returns focus to the hamburger" do
    sign_in_as users(:one)
    visit root_path
    resize_to_mobile

    find("button[aria-label='Toggle sources']").click
    assert_selector "aside#sidebar:not(.-translate-x-full)", wait: 5
    page.driver.click(320, 406)
    assert_selector "aside#sidebar.-translate-x-full", wait: 5

    focused_label = page.evaluate_script("document.activeElement.getAttribute('aria-label')")
    assert_equal "Toggle sources", focused_label
  end

  test "feed pagination links are 44px buttons" do
    sign_in_as users(:one)
    visit root_path

    if page.has_css?("a", text: "Older →")
      older = find("a", text: "Older →")
      height = older.evaluate_script("this.getBoundingClientRect().height")
      assert_operator height, :>=, 44, "pagination link got #{height}"
    end
  end
end
