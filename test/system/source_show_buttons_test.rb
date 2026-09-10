require "application_system_test_case"

class SourceShowButtonsTest < ApplicationSystemTestCase
  test "all source action buttons use consistent bordered style" do
    sign_in_as users(:one)
    visit source_path(sources(:youtube))

    action_cluster = find("[data-test='source-actions']")

    # Every action button/link should have border-2 class
    action_cluster.all(":scope > button, :scope > a", visible: false).each do |child|
      classes = child[:class] || ""
      assert_includes(classes, "border-2",
             "button should have border-2 class for consistent style, got: #{classes}")
    end
    # The collection menu button (inside its dropdown wrapper) should also be bordered
    collection_button = action_cluster.find("div[data-controller='dropdown'] > button", visible: false)
    assert_includes(collection_button[:class], "border-2",
           "collection menu button should have border-2 class")
  end

  test "source action buttons have icons" do
    sign_in_as users(:one)
    visit source_path(sources(:youtube))

    action_cluster = find("[data-test='source-actions']")
    # Each button/link should contain an svg (Phosphor icon)
    action_cluster.all(":scope > button, :scope > a", visible: false).each do |child|
      assert child.has_selector?("svg", visible: false),
             "button should contain an svg icon"
    end
    collection_button = action_cluster.find("div[data-controller='dropdown'] > button", visible: false)
    assert collection_button.has_selector?("svg", visible: false),
           "collection menu button should contain an svg icon"
  end

  test "delete button uses cerise danger color" do
    sign_in_as users(:one)
    visit source_path(sources(:youtube))

    delete_link = find("[data-test='source-actions'] a", text: /Delete/i)
    assert_includes delete_link[:class], "cerise"
  end

  test "collection menu button label renders icon and text inline" do
    sign_in_as users(:one)
    visit source_path(sources(:youtube))

    frame = find("div[data-controller='dropdown'] > button turbo-frame", visible: false)
    assert_includes frame[:class], "inline-flex"
    assert_includes frame[:class], "items-center"
  end
end
