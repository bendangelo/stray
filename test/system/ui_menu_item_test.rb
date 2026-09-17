require "test_helper"
require "application_system_test_case"

class UiMenuItemTest < ApplicationSystemTestCase
  test "dropdown menu items are at least 44px tall" do
    sign_in_as users(:one)
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      find("button[aria-controls^='item-actions-']").click
      link = find("div[data-dropdown-target='menu'] a", text: "Open details")
      height = link.evaluate_script("this.getBoundingClientRect().height")
      assert_operator height, :>=, 44,
        "menu item must be at least 44px tall for touch, got #{height}"
    end
  end

  test "hovered menu item gets a visible carrot highlight" do
    sign_in_as users(:one)
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      find("button[aria-controls^='item-actions-']").click
      link = find("div[data-dropdown-target='menu'] a", text: "Open details")
      link.hover
      bg = link.evaluate_script("getComputedStyle(this).backgroundColor")
      assert_equal "rgb(255, 237, 223)", bg,
        "hover highlight must be carrot-100 #FFEDDF, got #{bg}"
    end
  end

  test "keyboard-focused menu item gets the same highlight" do
    sign_in_as users(:one)
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      find("button[aria-controls^='item-actions-']").click
      page.driver.browser.keyboard.type(:Tab)
      link = find("div[data-dropdown-target='menu'] a", text: "Open details")
      assert_equal "Open details", page.evaluate_script("document.activeElement.textContent.trim()"),
        "expected the first menu item to be focusable via keyboard"
      bg = link.evaluate_script("getComputedStyle(this).backgroundColor")
      assert_equal "rgb(255, 237, 223)", bg,
        ":focus-visible needs the carrot highlight for keyboard nav, got #{bg}"
    end
  end
end
