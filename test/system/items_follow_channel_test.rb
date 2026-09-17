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

  test "follow channel button is not visible on a non-video saved_video item" do
    sign_in_as(users(:one))
    source = Source.create!(user: users(:one), kind: :saved_video,
      url: "https://example.com/blog/post", external_id: "post1", name: "Generic Saved")
    item = Item.create!(source: source, user: users(:one), external_id: "post1",
      title: "Generic Saved", url: "https://example.com/blog/post")

    Bridges::GenericList.stub(:detect, nil) do
      visit item_path(item)

      assert_no_text "Follow channel"
    end
  end

  test "saved_video YouTube item renders the video embed on the show page" do
    sign_in_as(users(:one))
    item = items(:video_saved_yt)

    visit item_path(item)

    assert_selector "iframe[src*='youtube.com/embed/savevid1']", wait: 5
  end
end
