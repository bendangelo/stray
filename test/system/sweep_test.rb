require "test_helper"
require "application_system_test_case"

class SweepTest < ApplicationSystemTestCase
  test "auth inputs are 44px tall" do
    visit new_session_path

    height = find("input[type='email']").evaluate_script("this.getBoundingClientRect().height")
    assert_operator height, :>=, 44
  end

  test "public source page uses palette colors not browser defaults" do
    source = sources(:youtube)
    visit public_source_path(slug: source.slug)

    link = find("a", text: "RSS feed")
    color = link.evaluate_script("getComputedStyle(this).color")
    assert_equal "rgb(255, 109, 4)", color, "public links must be carrot-600 #FF6D04, got #{color}"
  end

  test "sources index primary buttons are 44px" do
    sign_in_as users(:one)
    visit sources_path

    btn = find("a", text: "+ Add source")
    height = btn.evaluate_script("this.getBoundingClientRect().height")
    assert_operator height, :>=, 44
  end

  test "empty states share the partial card" do
    sign_in_as users(:two)
    visit collections_path

    card = find("main .border-3.bg-athens-400.p-8")
    assert_includes card[:class], "p-8"
  end
end
