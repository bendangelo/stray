require "test_helper"
require "application_system_test_case"

class ResponsiveLayoutTest < ApplicationSystemTestCase
  test "html has lang attribute" do
    visit about_path

    assert_equal "en", find("html")[:lang]
  end

  test "body has overflow-x hidden to prevent horizontal scroll" do
    visit about_path

    assert_includes find("body")[:class], "overflow-x-hidden"
  end

  test "footer is not fixed so it does not overlap content" do
    visit new_session_path

    footer = find("footer")
    footer_classes = footer[:class]

    refute_includes footer_classes, "fixed", "footer should not be fixed"
  end

  test "layout uses min-h-screen wrapper so footer sits at bottom on short pages" do
    visit about_path

    # The body's main content wrapper should have min-h-screen to push footer down
    wrapper_classes = find("body > div:first-child")[:class]
    assert_includes wrapper_classes, "min-h-screen",
           "content wrapper should have min-h-screen so footer pins to viewport bottom"
  end
end
