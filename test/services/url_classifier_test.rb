require "test_helper"

class UrlClassifierTest < ActiveSupport::TestCase
  test "classifies YouTube channel handle URL" do
    c = UrlClassifier.classify("https://www.youtube.com/@RickAstley")
    assert_equal :youtube_channel, c.category
    assert_equal "youtube_channel", c.source_kind
    assert_equal Extractors::YoutubeRss, c.extractor_class
    assert_equal Youtube::ChannelResolver, c.resolver
  end

  test "classifies YouTube channel /c/ URL" do
    c = UrlClassifier.classify("https://www.youtube.com/c/RickAstley")
    assert_equal :youtube_channel, c.category
  end

  test "classifies YouTube channel /user/ URL" do
    c = UrlClassifier.classify("https://www.youtube.com/user/RickAstley")
    assert_equal :youtube_channel, c.category
  end

  test "classifies YouTube channel /channel/UC URL" do
    c = UrlClassifier.classify("https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw")
    assert_equal :youtube_channel, c.category
  end

  test "classifies youtu.be channel URL" do
    c = UrlClassifier.classify("https://youtu.be/@RickAstley")
    assert_equal :youtube_channel, c.category
  end

  test "classifies YouTube watch video URL" do
    c = UrlClassifier.classify("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    assert_equal :youtube_video, c.category
    assert_equal "youtube_channel", c.source_kind
  end

  test "classifies youtu.be video URL" do
    c = UrlClassifier.classify("https://youtu.be/dQw4w9WgXcQ")
    assert_equal :youtube_video, c.category
  end

  test "classifies RSS feed URL" do
    c = UrlClassifier.classify("https://blog.example.com/feed")
    assert_equal :rss_feed, c.category
    assert_equal "rss_feed", c.source_kind
    assert_equal Extractors::RssAtom, c.extractor_class
  end

  test "classifies stray collection manifest URL" do
    c = UrlClassifier.classify("https://stray.example.com/c/abc123def456ghi789jkl012/manifest.json")
    assert_equal :stray_collection, c.category
  end

  test "classifies friendly stray collection URL" do
    c = UrlClassifier.classify("https://stray.example.com/c/abc123def456ghi789jkl012")
    assert_equal :stray_collection, c.category
  end

  test "classifies video host URL" do
    c = UrlClassifier.classify("https://www.bitchute.com/video/abc123")
    assert_equal :video_channel, c.category
    assert_equal "video_channel", c.source_kind
    assert_equal Extractors::YtDlp, c.extractor_class
  end

  test "classifies generic page URL" do
    c = UrlClassifier.classify("https://example.com/blog/hello-world")
    assert_equal :generic_page, c.category
    assert_equal "generic_page", c.source_kind
    assert_equal Extractors::GenericPage, c.extractor_class
  end

  test "classifies YouTube RSS feed URL as youtube_channel" do
    c = UrlClassifier.classify("https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw")
    assert_equal :youtube_channel, c.category
  end

  test "returns nil for non-http URL" do
    assert_nil UrlClassifier.classify("ftp://example.com/file")
  end
end
