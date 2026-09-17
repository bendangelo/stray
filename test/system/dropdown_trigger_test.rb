require "test_helper"
require "application_system_test_case"

class DropdownTriggerTest < ApplicationSystemTestCase
  def trigger_height_for(selector)
    find(selector, match: :first).evaluate_script("this.getBoundingClientRect().height")
  end

  test "item card actions trigger is at least 44px" do
    sign_in_as users(:one)
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      height = trigger_height_for("button[aria-controls^='item-actions-']")
      assert_operator height, :>=, 44, "item actions trigger got #{height}"
    end
  end

  test "sidebar source menu trigger is at least 44px" do
    sign_in_as users(:one)
    visit root_path

    height = trigger_height_for("button[aria-controls^='sidebar-source-menu-']")
    assert_operator height, :>=, 44, "sidebar source trigger got #{height}"
  end

  test "navbar hamburger is at least 44px" do
    sign_in_as users(:one)
    visit root_path
    resize_to_mobile

    height = trigger_height_for("nav button[aria-label='Toggle sources']")
    assert_operator height, :>=, 44, "hamburger got #{height}"
  end

  test "account dropdown trigger is at least 44px" do
    sign_in_as users(:one)
    visit root_path

    height = trigger_height_for("nav button[aria-label='Account']")
    assert_operator height, :>=, 44, "account trigger got #{height}"
  end
end
