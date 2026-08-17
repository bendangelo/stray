require "test_helper"

class Extractors::YoutubeRssTest < ActiveSupport::TestCase
  test "matches? returns true for YouTube RSS feed URLs" do
    assert Extractors::YoutubeRss.matches?("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
    assert Extractors::YoutubeRss.matches?("https://youtube.com/feeds/videos.xml?channel_id=UC123")
  end

  test "matches? returns false for non-RSS YouTube URLs" do
    assert_not Extractors::YoutubeRss.matches?("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    assert_not Extractors::YoutubeRss.matches?("https://www.youtube.com/@channel")
    assert_not Extractors::YoutubeRss.matches?("https://www.youtube.com/channel/UC123")
  end

  test "matches? returns false for non-YouTube URLs" do
    assert_not Extractors::YoutubeRss.matches?("https://example.com/feed.xml")
    assert_not Extractors::YoutubeRss.matches?("https://bitchute.com/channel/abc")
  end

  test "handles_kind? returns true for youtube_channel" do
    assert Extractors::YoutubeRss.handles_kind?("youtube_channel")
  end

  test "handles_kind? returns false for other kinds" do
    assert_not Extractors::YoutubeRss.handles_kind?("rss_feed")
    assert_not Extractors::YoutubeRss.handles_kind?("video_channel")
  end

  test "extract returns array of ExtractedContent from RSS feed" do
    VCR.use_cassette("extractors/youtube_rss_feed") do
      extractor = Extractors::YoutubeRss.new
      results = extractor.extract("https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw")

      assert_equal 2, results.size
      first = results.first
      assert_equal "dQw4w9WgXcQ", first.external_id
      assert_equal "https://www.youtube.com/watch?v=dQw4w9WgXcQ", first.url
      assert_equal "Rick Astley - Never Gonna Give You Up (Official Music Video)", first.title
      assert_equal "The official video for Never Gonna Give You Up by Rick Astley.", first.content_text
      assert_equal "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg", first.thumbnail_url
      assert_equal Time.parse("2009-10-25T00:00:00+00:00"), first.published_at
      assert_nil first.duration
    end
  end

  test "extract includes creator_identity from feed author" do
    VCR.use_cassette("extractors/youtube_rss_feed") do
      extractor = Extractors::YoutubeRss.new
      results = extractor.extract("https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw")

      creator = results.first.creator_identity
      assert_equal "Rick Astley", creator.name
      assert_equal "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw", creator.url
      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", creator.external_id
    end
  end
end
