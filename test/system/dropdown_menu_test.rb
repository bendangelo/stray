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
        assert_equal "flex", link[:class].split.grep(/^flex/).first,
                     "menu item link must be a flex row, got: #{link[:class]}"
        refute link[:class].split.include?("dropdown_menu_item_class"),
               "literal 'dropdown_menu_item_class' must not leak into markup"
      end
    end
  end

  test "menu item link fills full menu width for reliable click target" do
    sign_in_as(users(:one))
    visit root_path

    within "##{dom_id(items(:video_one))}" do
      find("button[aria-controls^='item-actions-']").click
      menu = find("div[data-dropdown-target='menu']")
      link = find_link("Open details")

      metrics = menu.evaluate_script(<<~JS)
        (() => {
          const s = getComputedStyle(this);
          return {
            content: this.clientWidth - parseFloat(s.paddingLeft) - parseFloat(s.paddingRight),
            link: (() => {
              const a = this.querySelector("a");
              return a.getBoundingClientRect().width;
            })()
          };
        })()
      JS
      assert_in_delta metrics["content"], metrics["link"], 2,
                      "clickable link should span menu content width, got link=#{metrics['link']} content=#{metrics['content']}"
    end
  end

  test "sidebar source menu items use the helper classes" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    visit root_path

    within "#sidebar" do
      find("button[aria-controls='sidebar-source-menu-#{source.id}']").click
      within "#sidebar-source-menu-#{source.id}" do
        link = find_link("Edit")
        assert link[:class].split.include?("flex")
        assert link[:class].split.include?("items-center")
        assert link[:class].split.include?("w-full")
      end
    end
  end
end