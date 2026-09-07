require "test_helper"

class Bridges::OdyseeTest < ActiveSupport::TestCase
  test "extract_backfill is a no-op (RSS already returns ~50 videos)" do
    assert_nil Bridges::Odysee.new.extract_backfill("https://odysee.com/@samtime:1", limit: 50)
  end

  test "extract_feed_from_response maps a pre-fetched RSS body" do
    core = Minitest::Mock.new
    core.expect(:feed_from_rss, [ {
      url: "https://odysee.com/v1", title: "V1", external_id: "1", duration: 10,
      published_at: Time.now, thumbnail_url: "https://img.jpg", content_text: nil,
      content_html: nil, tags: [], views: nil, live: nil, is_short: nil,
      creator_identity: { name: "Chan", url: "https://odysee.com/@c:1", external_id: "c:1", thumbnail_url: nil }
    } ], [ "body", "https://odysee.com/@c:1" ])

    response = Struct.new(:status, :body, :headers).new(200, "body", {})

    Stray::Bridges::Odysee.stub(:new, core) do
      result = Bridges::Odysee.new.extract_feed_from_response(response, "https://odysee.com/@c:1")
      assert_equal 1, result.size
      assert_equal "1", result.first.external_id
    end
  end

  test "extract maps a single video page" do
    video_hash = {
      url: "https://odysee.com/@SkyLight33:7/some-video:49",
      title: "Test Odysee Video",
      external_id: "some-video:49",
      duration: 600,
      published_at: Time.now,
      thumbnail_url: "https://example.com/thumb.jpg",
      content_text: "A test video",
      content_html: nil,
      tags: [],
      views: nil,
      live: nil,
      is_short: nil,
      creator_identity: { name: "SkyLight33", url: "https://odysee.com/@SkyLight33:7", external_id: "SkyLight33:7", thumbnail_url: nil }
    }

    core = Minitest::Mock.new
    core.expect(:video_page, video_hash, [ "https://odysee.com/@SkyLight33:7/some-video:49" ])

    Stray::Bridges::Odysee.stub(:new, core) do
      content = Bridges::Odysee.new.extract("https://odysee.com/@SkyLight33:7/some-video:49")
      assert_equal "some-video:49", content.external_id
      assert_equal "Test Odysee Video", content.title
      assert_equal "SkyLight33", content.creator_identity.name
      assert_equal "SkyLight33:7", content.creator_identity.external_id
    end
  end
end
