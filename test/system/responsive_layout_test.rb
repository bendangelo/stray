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
end
