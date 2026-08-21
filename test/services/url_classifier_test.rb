require "test_helper"

class UrlClassifierTest < ActiveSupport::TestCase
  test "classifies YouTube channel handle URL" do
    c = UrlClassifier.classify("https://www.youtube.com/@RickAstley")
    assert_equal :youtube_channel, c.category
    assert_equal "youtube_channel", c.source_kind
    assert_equal Bridges::YoutubeRss, c.extractor_class
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
    assert_equal Bridges::RssAtom, c.extractor_class
  end

  test "classifies stray collection manifest URL" do
    c = UrlClassifier.classify("https://stray.example.com/c/abc123def456ghi789jkl012/manifest.json")
    assert_equal :stray_collection, c.category
  end

  test "classifies friendly stray collection URL" do
    c = UrlClassifier.classify("https://stray.example.com/c/abc123def456ghi789jkl012")
    assert_equal :stray_collection, c.category
  end

  test "classifies bitchute video URL" do
    c = UrlClassifier.classify("https://www.bitchute.com/video/abc123")
    assert_equal :bitchute_video, c.category
    assert_equal "bitchute_channel", c.source_kind
    assert_equal Bridges::Bitchute, c.extractor_class
  end

  test "classifies bitchute channel URL" do
    c = UrlClassifier.classify("https://www.bitchute.com/channel/Foo")
    assert_equal :bitchute_channel_feed, c.category
    assert_equal "bitchute_channel", c.source_kind
    assert_equal Bridges::Bitchute, c.extractor_class
  end

  test "classifies generic page URL" do
    Bridges::GenericList.stub(:detect, nil) do
      c = UrlClassifier.classify("https://example.com/blog/hello-world")
      assert_equal :generic_page, c.category
      assert_equal "generic_page", c.source_kind
      assert_equal Bridges::GenericPage, c.extractor_class
    end
  end

  test "classifies YouTube RSS feed URL as youtube_channel" do
    c = UrlClassifier.classify("https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw")
    assert_equal :youtube_channel, c.category
  end

  test "returns nil for non-http URL" do
    assert_nil UrlClassifier.classify("ftp://example.com/file")
  end

  test "classifies rumble channel URL" do
    c = UrlClassifier.classify("https://rumble.com/c/BrightInsight")
    assert_equal :rumble_channel_feed, c.category
    assert_equal "rumble_channel", c.source_kind
    assert_equal Bridges::Rumble, c.extractor_class
  end

  test "classifies rumble video URL" do
    c = UrlClassifier.classify("https://rumble.com/v7a8neu.html")
    assert_equal :rumble_video, c.category
    assert_equal "rumble_channel", c.source_kind
    assert_equal Bridges::Rumble, c.extractor_class
  end

  test "classifies odysee channel URL" do
    c = UrlClassifier.classify("https://odysee.com/@samtime:1")
    assert_equal :odysee_channel, c.category
    assert_equal "odysee_channel", c.source_kind
    assert_equal Bridges::Odysee, c.extractor_class
  end

  test "classifies peertube channel URL" do
    c = UrlClassifier.classify("https://tilvids.com/video-channels/fedi")
    assert_equal :peertube_channel_feed, c.category
    assert_equal "peertube_channel", c.source_kind
    assert_equal Bridges::Peertube, c.extractor_class
  end

  test "classifies peertube account /a/ URL as channel feed" do
    c = UrlClassifier.classify("https://tube.xy-space.de/a/voxpopuli")
    assert_equal :peertube_channel_feed, c.category
    assert_equal "peertube_channel", c.source_kind
    assert_equal Bridges::Peertube, c.extractor_class
  end

  test "classifies peertube video URL" do
    c = UrlClassifier.classify("https://tilvids.com/w/abc123")
    assert_equal :peertube_video, c.category
    assert_equal "peertube_channel", c.source_kind
    assert_equal Bridges::Peertube, c.extractor_class
  end

  test "classifies generic list page when GenericList detects a list" do
    Bridges::GenericList.stub(:detect, 5) do
      c = UrlClassifier.classify("https://example.com/blog")
      assert_equal :generic_list, c.category
      assert_equal "generic_list", c.source_kind
      assert_equal Bridges::GenericList, c.extractor_class
    end
  end

  test "classifies generic page (bookmark) when GenericList detects no list" do
    Bridges::GenericList.stub(:detect, nil) do
      c = UrlClassifier.classify("https://example.com/blog")
      assert_equal :generic_page, c.category
      assert_equal "generic_page", c.source_kind
      assert_equal Bridges::GenericPage, c.extractor_class
    end
  end

  test "classifies generic page when GenericList probe raises rate budget exhausted" do
    Bridges::GenericList.stub(:detect, ->(_url) { raise Stray::RateBudgetExhausted, "Rate budget exhausted for example.com" }) do
      c = UrlClassifier.classify("https://example.com/blog")
      assert_equal :generic_page, c.category
      assert_equal "generic_page", c.source_kind
      assert_equal Bridges::GenericPage, c.extractor_class
    end
  end

  test "classifies generic page when GenericList probe raises extraction error" do
    Bridges::GenericList.stub(:detect, ->(_url) { raise Stray::ExtractionError, "page fetch failed" }) do
      c = UrlClassifier.classify("https://example.com/blog")
      assert_equal :generic_page, c.category
      assert_equal "generic_page", c.source_kind
      assert_equal Bridges::GenericPage, c.extractor_class
    end
  end
end
