require "test_helper"
require "application_system_test_case"

class ItemStateVisualsTest < ApplicationSystemTestCase
  test "unseen item shows a mint dot badge on the thumbnail" do
    sign_in_as(users(:one))
    item = items(:video_one)
    assert item.unseen?

    visit source_path(item.source)

    within "##{dom_id(item)}" do
      assert_selector ".bg-mint.rounded-full", count: 1
    end
  end

  test "seen item does not show a mint dot badge" do
    sign_in_as(users(:one))
    item = items(:video_one)
    item.update!(state: :seen)

    visit source_path(item.source)

    within "##{dom_id(item)}" do
      assert_no_selector ".bg-mint.rounded-full"
    end
  end

  test "unseen item overflow menu has Mark as seen button" do
    sign_in_as(users(:one))
    item = items(:video_one)
    assert item.unseen?

    visit source_path(item.source)

    within "##{dom_id(item)}" do
      find("button[aria-controls^='item-actions-']").click
      assert_text "Mark as seen"
    end
  end

  test "seen item overflow menu does not have Mark as seen button" do
    sign_in_as(users(:one))
    item = items(:video_one)
    item.update!(state: :seen)

    visit source_path(item.source)

    within "##{dom_id(item)}" do
      find("button[aria-controls^='item-actions-']").click
      assert_no_text "Mark as seen"
    end
  end

  test "overflow menu says Hide from feed not Hide" do
    sign_in_as(users(:one))
    item = items(:video_one)

    visit source_path(item.source)

    within "##{dom_id(item)}" do
      find("button[aria-controls^='item-actions-']").click
      assert_text "Hide from feed"
      assert_no_text /^Hide$/
    end
  end

  test "clicking Mark as seen removes the mint dot" do
    sign_in_as(users(:one))
    item = items(:video_one)
    assert item.unseen?

    visit source_path(item.source)

    within "##{dom_id(item)}" do
      assert_selector ".bg-mint.rounded-full", count: 1
      find("button[aria-controls^='item-actions-']").click
      click_on "Mark as seen"
    end

    within "##{dom_id(item)}" do
      assert_no_selector ".bg-mint.rounded-full"
    end
    assert item.reload.seen?
  end
end
