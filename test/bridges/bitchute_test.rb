require "test_helper"

class Bridges::BitchuteTest < ActiveSupport::TestCase
  HASHES = [
    {
      url: "https://www.bitchute.com/video/vid1", title: "Video 1", external_id: "vid1",
      duration: 910, published_at: Time.parse("2026-09-07T08:25:20Z"),
      thumbnail_url: "https://img.jpg", content_text: "desc", content_html: nil,
      tags: [], views: 609, live: nil, is_short: nil,
      creator_identity: { name: nil, url: "https://www.bitchute.com/channel/C1", external_id: "C1", thumbnail_url: nil }
    }
  ].freeze

  test "extract_feed maps channel_feed hashes to ExtractedContent" do
    core = Minitest::Mock.new
    core.expect(:channel_feed, HASHES, [ "https://www.bitchute.com/channel/Foo" ])
    Stray::Bridges::Bitchute.stub(:new, core) do
      result = Bridges::Bitchute.new.extract_feed("https://www.bitchute.com/channel/Foo")

      assert_equal 1, result.size
      assert_equal "vid1", result.first.external_id
      assert_equal "Video 1", result.first.title
      assert_equal "https://www.bitchute.com/video/vid1", result.first.url
    end
  end

  test "extract_feed_from_response delegates to the API and ignores the pre-fetched body" do
    core = Minitest::Mock.new
    core.expect(:channel_feed, HASHES, [ "https://www.bitchute.com/channel/Foo" ])
    response = Struct.new(:status, :body, :headers).new(200, "<html><script>spa</script></html>", {})
    Stray::Bridges::Bitchute.stub(:new, core) do
      result = Bridges::Bitchute.new.extract_feed_from_response(response, "https://www.bitchute.com/channel/Foo")

      assert_equal "vid1", result.first.external_id
    end
  end

  test "extract_backfill accepts cursor and passes limit to channel_feed" do
    core = Stray::Bridges::Bitchute.new
    captured = nil
    Stray::Bridges::Bitchute.stub(:new, core) do
      core.stub(:channel_feed, lambda { |url, limit:| captured = [ url, limit ]; HASHES }) do
        result = Bridges::Bitchute.new.extract_backfill("https://www.bitchute.com/channel/Foo", limit: 50, cursor: nil)

        assert_equal 1, result.size
        assert_equal "vid1", result.first.external_id
        assert_equal "https://www.bitchute.com/channel/Foo", captured.first
        assert_equal 50, captured.last
      end
    end
  end

  test "extract maps video_page detail to ExtractedContent with creator" do
    detail = {
      url: "https://www.bitchute.com/video/vid1", title: "Video 1", external_id: "vid1",
      duration: 910, published_at: Time.parse("2026-09-07T08:25:20Z"),
      thumbnail_url: "https://img.jpg", content_text: "desc", content_html: nil,
      tags: %w[politics news], views: 609, live: nil, is_short: nil,
      creator_identity: { name: "Stew Peters", url: "https://www.bitchute.com/channel/C1", external_id: "C1", thumbnail_url: nil }
    }
    core = Stray::Bridges::Bitchute.new
    Stray::Bridges::Bitchute.stub(:new, core) do
      core.stub(:video_page, detail) do
        result = Bridges::Bitchute.new.extract("https://www.bitchute.com/video/vid1")

        assert_equal "vid1", result.external_id
        assert_equal "Video 1", result.title
        assert_equal "Stew Peters", result.creator_identity.name
        assert_equal "C1", result.creator_identity.external_id
      end
    end
  end

  test "handles_kind? matches bitchute_channel" do
    assert Bridges::Bitchute.handles_kind?("bitchute_channel")
    assert_not Bridges::Bitchute.handles_kind?("rumble_channel")
  end
end
