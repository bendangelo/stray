require "test_helper"

class Bridges::RemoteCollectionTest < ActiveSupport::TestCase
  test "handles_kind? returns true for stray_collection" do
    assert Bridges::RemoteCollection.handles_kind?("stray_collection")
  end

  test "handles_kind? returns false for other kinds" do
    assert_not Bridges::RemoteCollection.handles_kind?("rss_feed")
    assert_not Bridges::RemoteCollection.handles_kind?("youtube_channel")
  end

  test "matches? returns true for manifest.json URLs" do
    assert Bridges::RemoteCollection.matches?("https://stray.example.com/c/abc/manifest.json")
  end

  test "matches? returns false for non-manifest URLs" do
    assert_not Bridges::RemoteCollection.matches?("https://example.com/feed.xml")
  end

  test "manifest_url_for returns URL as-is for manifest URLs" do
    url = "https://stray.example.com/c/abc/manifest.json"
    assert_equal url, Bridges::RemoteCollection.manifest_url_for(url)
  end

  test "manifest_url_for converts friendly /c/:slug URL to manifest URL" do
    assert_equal "https://stray.example.com/c/remotetokensecret1234567/manifest.json",
      Bridges::RemoteCollection.manifest_url_for("https://stray.example.com/c/remotetokensecret1234567")
  end

  test "manifest_url_for returns nil for non-collection URLs" do
    assert_nil Bridges::RemoteCollection.manifest_url_for("https://example.com/feed.xml")
    assert_nil Bridges::RemoteCollection.manifest_url_for("not a url")
  end

  test "extract_feed returns FeedResult with items from manifest" do
    VCR.use_cassette("remote_collection/manifest_first_page") do
      extractor = Bridges::RemoteCollection.new
      result = extractor.extract_feed("https://stray.example.com/c/abc/manifest.json")

      assert result.is_a?(Stray::Bridge::FeedResult)
      assert_equal 2, result.items.size
      assert_equal "First Item", result.items.first.title
      assert_equal "https://stray.example.com/posts/1", result.items.first.url
      assert_equal "item1", result.items.first.external_id
      assert_equal [ "econ", "policy" ], result.items.first.tags
      assert result.has_more
      assert result.next_cursor.present?
    end
  end

  test "extract_feed on last page returns has_more false" do
    VCR.use_cassette("remote_collection/manifest_second_page") do
      extractor = Bridges::RemoteCollection.new
      result = extractor.extract_feed("https://stray.example.com/c/abc/manifest.json?cursor=abc")

      assert result.is_a?(Stray::Bridge::FeedResult)
      assert_not result.has_more
      assert_nil result.next_cursor
    end
  end
end
