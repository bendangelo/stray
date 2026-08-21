require "test_helper"
require "application_system_test_case"

class ItemsFollowChannelSystemTest < ApplicationSystemTestCase
  test "follow channel button is visible on a saved_video YouTube item" do
    sign_in_as(users(:one))
    item = items(:video_saved_yt)

    visit item_path(item)

    assert_text "Follow channel"
  end

  test "follow channel button is not visible on a youtube_channel item" do
    sign_in_as(users(:one))
    item = items(:video_one)

    visit item_path(item)

    assert_no_text "Follow channel"
  end

  test "follow channel button is not visible on a non-YouTube saved_video item" do
    sign_in_as(users(:one))
    source = Source.create!(user: users(:one), kind: :saved_video,
      url: "https://bitchute.com/video/bcvid9", external_id: "bcvid9", name: "BC Saved")
    item = Item.create!(source: source, user: users(:one), external_id: "bcvid9",
      title: "BC Saved", url: "https://bitchute.com/video/bcvid9")

    visit item_path(item)

    assert_no_text "Follow channel"
  end
end
