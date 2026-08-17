require "test_helper"

class Extractors::RemoteCollectionTest < ActiveSupport::TestCase
  test "handles_kind? returns true for stray_collection" do
    assert Extractors::RemoteCollection.handles_kind?("stray_collection")
  end

  test "handles_kind? returns false for other kinds" do
    assert_not Extractors::RemoteCollection.handles_kind?("rss_feed")
    assert_not Extractors::RemoteCollection.handles_kind?("youtube_channel")
  end

  test "matches? returns true for manifest.json URLs" do
    assert Extractors::RemoteCollection.matches?("https://stray.example.com/c/abc/manifest.json")
  end

  test "matches? returns false for non-manifest URLs" do
    assert_not Extractors::RemoteCollection.matches?("https://example.com/feed.xml")
  end

  test "extract_feed returns FeedResult with items from manifest" do
    VCR.use_cassette("remote_collection/manifest_first_page") do
      extractor = Extractors::RemoteCollection.new
      result = extractor.extract_feed("https://stray.example.com/c/abc/manifest.json")

      assert result.is_a?(Extractor::FeedResult)
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
      extractor = Extractors::RemoteCollection.new
      result = extractor.extract_feed("https://stray.example.com/c/abc/manifest.json?cursor=abc")

      assert result.is_a?(Extractor::FeedResult)
      assert_not result.has_more
      assert_nil result.next_cursor
    end
  end

  test "extract_feed rejects non-manifest URL with UrlGuard" do
    UrlGuard.stub(:allowed?, false) do
      extractor = Extractors::RemoteCollection.new
      assert_raises(UrlGuard::Blocked) do
        extractor.extract_feed("http://localhost/c/abc/manifest.json")
      end
    end
  end
end
