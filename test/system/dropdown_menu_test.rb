require "test_helper"
require "application_system_test_case"

class DropdownMenuTest < ApplicationSystemTestCase
  test "menu items render icon and text inline on one line" do
    sign_in_as(users(:one))
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      find("button[aria-controls^='item-actions-']").click
      within "div[data-dropdown-target='menu']" do
        link = find_link("Open details")
        assert_equal "flex", link.evaluate_script("getComputedStyle(this).display"),
          "menu item link must be a flex row"
        refute link[:class].include?("dropdown_menu_item_class"),
          "literal helper name must not leak into markup"
      end
    end
  end

  test "menu item link fills full menu width and 44px height for reliable click target" do
    sign_in_as(users(:one))
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      find("button[aria-controls^='item-actions-']").click
      menu = find("div[data-dropdown-target='menu']")

      metrics = menu.evaluate_script(<<~JS)
        (() => {
          const s = getComputedStyle(this);
          const a = this.querySelector("a");
          const r = a.getBoundingClientRect();
          return { content: this.clientWidth - parseFloat(s.paddingLeft) - parseFloat(s.paddingRight), link: r.width };
        })()
      JS
      assert_in_delta metrics["content"], metrics["link"], 2,
        "clickable link should span menu content width"

      link = find_link("Open details")
      height = link.evaluate_script("this.getBoundingClientRect().height")
      assert_operator height, :>=, 44
    end
  end

  test "sidebar source menu items are 44px flex rows" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    visit root_path

    within "#sidebar" do
      find("button[aria-controls='sidebar-source-menu-#{source.id}']").click
      within "#sidebar-source-menu-#{source.id}" do
        link = find_link("Edit")
        assert_equal "flex", link.evaluate_script("getComputedStyle(this).display")
        height = link.evaluate_script("this.getBoundingClientRect().height")
        assert_operator height, :>=, 44
      end
    end
  end
end
