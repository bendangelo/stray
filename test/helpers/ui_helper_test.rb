require "test_helper"

class UiHelperTest < ActionView::TestCase
  test "ui_menu_item returns the shared class hook" do
    assert_equal "ui-menu-item", ui_menu_item
  end

  test "ui_menu_item danger variant adds the danger modifier" do
    assert_equal "ui-menu-item ui-menu-item--danger", ui_menu_item(danger: true)
  end

  test "ui_button primary default is h-11 border-3 carrot" do
    classes = ui_button.split
    assert_includes classes, "inline-flex"
    assert_includes classes, "items-center"
    assert_includes classes, "justify-center"
    assert_includes classes, "gap-1.5"
    assert_includes classes, "h-11"
    assert_includes classes, "px-4"
    assert_includes classes, "rounded-md"
    assert_includes classes, "border-3"
    assert_includes classes, "border-charcoal"
    assert_includes classes, "bg-carrot-500"
    assert_includes classes, "text-white"
    assert_includes classes, "font-bold"
    assert_includes classes, "text-sm"
    assert_includes classes, "cursor-pointer"
  end

  test "ui_button secondary uses card surface" do
    classes = ui_button(variant: :secondary).split
    assert_includes classes, "bg-athens-400"
    assert_includes classes, "text-charcoal"
    refute_includes classes, "bg-carrot-500"
  end

  test "ui_button danger uses cerise text on card surface" do
    classes = ui_button(variant: :danger).split
    assert_includes classes, "bg-athens-400"
    assert_includes classes, "text-cerise"
  end

  test "ui_button sm size is h-9" do
    assert_includes ui_button(size: :sm).split, "h-9"
  end

  test "ui_button lg size is h-12" do
    assert_includes ui_button(size: :lg).split, "h-12"
  end

  test "ui_input returns the standard field classes" do
    classes = ui_input.split
    assert_includes classes, "w-full"
    assert_includes classes, "h-11"
    assert_includes classes, "px-3"
    assert_includes classes, "bg-athens-400"
    assert_includes classes, "border-3"
    assert_includes classes, "border-charcoal"
    assert_includes classes, "rounded-md"
    assert_includes classes, "text-sm"
    assert_includes classes, "text-charcoal"
    assert_includes classes, "focus:outline-none"
  end

  test "ui_label returns the standard label classes" do
    classes = ui_label.split
    assert_includes classes, "block"
    assert_includes classes, "text-sm"
    assert_includes classes, "font-bold"
    assert_includes classes, "text-charcoal"
    assert_includes classes, "mb-1"
  end

  test "ui_card default padding is p-4" do
    assert_includes ui_card.split, "p-4"
  end

  test "ui_card compact padding is p-3" do
    assert_includes ui_card(padding: :compact).split, "p-3"
  end

  test "ui_page form tier is max-w-3xl" do
    assert_includes ui_page.split, "max-w-3xl"
  end

  test "ui_page list tier is max-w-6xl" do
    assert_includes ui_page(tier: :list).split, "max-w-6xl"
  end

  test "ui_page reader tier is max-w-screen-xl" do
    assert_includes ui_page(tier: :reader).split, "max-w-screen-xl"
  end

  test "ui_select returns the standard select classes" do
    classes = ui_select.split
    assert_includes classes, "w-full"
    assert_includes classes, "h-11"
    assert_includes classes, "bg-athens-400"
    assert_includes classes, "border-3"
  end

  test "ui_flash alert variant is cerise" do
    assert_includes ui_flash(:alert).split, "border-cerise"
    assert_includes ui_flash(:alert).split, "text-cerise"
  end

  test "ui_flash notice variant is mint" do
    assert_includes ui_flash(:notice).split, "border-mint-500"
    assert_includes ui_flash(:notice).split, "text-mint-700"
  end
end
