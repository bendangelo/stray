require "test_helper"

class Bridges::RssAtomTest < ActiveSupport::TestCase
  test "matches? returns true for common RSS feed URL patterns" do
    assert Bridges::RssAtom.matches?("https://example.com/feed.xml")
    assert Bridges::RssAtom.matches?("https://example.com/feed.rss")
    assert Bridges::RssAtom.matches?("https://example.com/blog/atom")
    assert Bridges::RssAtom.matches?("https://example.com/rss")
    assert Bridges::RssAtom.matches?("https://example.com/feeds/posts")
  end

  test "matches? returns false for non-feed URLs" do
    assert_not Bridges::RssAtom.matches?("https://example.com/blog/post-1")
    assert_not Bridges::RssAtom.matches?("https://example.com/about")
  end

  test "handles_kind? returns true for rss_feed" do
    assert Bridges::RssAtom.handles_kind?("rss_feed")
  end

  test "handles_kind? returns false for other kinds" do
    assert_not Bridges::RssAtom.handles_kind?("youtube_channel")
    assert_not Bridges::RssAtom.handles_kind?("video_channel")
  end

  test "extract parses RSS feed and returns Stray::ExtractedContent array" do
    PoliteCrawl.stub(:sleep, nil) do
      VCR.use_cassette("extractors/rss_atom/feed_xml") do
        extractor = Bridges::RssAtom.new
        results = extractor.extract("https://example.com/feed.xml")

        assert_equal 2, results.size
        assert_equal "First Post", results[0].title
        assert_equal "https://example.com/posts/1", results[0].url
        assert_equal "https://example.com/posts/1", results[0].external_id
        assert_equal "Content of first post", results[0].content_text
        assert_nil results[0].duration
      end
    end
  end

  test "extract_feed delegates to extract" do
    PoliteCrawl.stub(:sleep, nil) do
      VCR.use_cassette("extractors/rss_atom/rss") do
        extractor = Bridges::RssAtom.new
        results = extractor.extract_feed("https://example.com/rss")
        assert_equal 1, results.size
      end
    end
  end

  test "http_client sends a browser User-Agent and Accept-Language" do
    client = Bridges::RssAtom.new.send(:http_client)

    assert_equal Bridges::RssAtom::BROWSER_UA, client.headers["User-Agent"]
    assert_equal "en", client.headers["Accept-Language"]
  end

  test "extract includes creator_identity from feed metadata" do
    PoliteCrawl.stub(:sleep, nil) do
      VCR.use_cassette("extractors/rss_atom/feed") do
        extractor = Bridges::RssAtom.new
        results = extractor.extract("https://example.com/feed")

        creator = results.first.creator_identity
        assert_equal "Test Blog", creator.name
        assert_equal "https://example.com", creator.url
      end
    end
  end
end
