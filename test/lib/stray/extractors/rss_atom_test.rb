require "test_helper"

class Stray::Extractors::RssAtomTest < ActiveSupport::TestCase
  test "matches? returns true for common RSS feed URL patterns" do
    assert Stray::Extractors::RssAtom.matches?("https://example.com/feed.xml")
    assert Stray::Extractors::RssAtom.matches?("https://example.com/feed.rss")
    assert Stray::Extractors::RssAtom.matches?("https://example.com/blog/atom")
    assert Stray::Extractors::RssAtom.matches?("https://example.com/rss")
    assert Stray::Extractors::RssAtom.matches?("https://example.com/feeds/posts")
  end

  test "matches? returns false for non-feed URLs" do
    assert_not Stray::Extractors::RssAtom.matches?("https://example.com/blog/post-1")
    assert_not Stray::Extractors::RssAtom.matches?("https://example.com/about")
  end

  test "handles_kind? returns true for rss_feed" do
    assert Stray::Extractors::RssAtom.handles_kind?("rss_feed")
  end

  test "handles_kind? returns false for other kinds" do
    assert_not Stray::Extractors::RssAtom.handles_kind?("youtube_channel")
    assert_not Stray::Extractors::RssAtom.handles_kind?("video_channel")
  end

  test "extract parses RSS feed and returns ExtractedContent array" do
    rss_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Blog</title>
          <link>https://example.com</link>
          <description>A test blog</description>
          <item>
            <title>First Post</title>
            <link>https://example.com/posts/1</link>
            <description>Content of first post</description>
            <pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
            <guid>https://example.com/posts/1</guid>
          </item>
          <item>
            <title>Second Post</title>
            <link>https://example.com/posts/2</link>
            <description>Content of second post</description>
            <pubDate>Tue, 02 Jan 2024 00:00:00 GMT</pubDate>
            <guid>https://example.com/posts/2</guid>
          </item>
        </channel>
      </rss>
    XML

    stub_request(:get, "https://example.com/feed.xml")
      .to_return(body: rss_xml, headers: { "Content-Type" => "application/rss+xml" })

    extractor = Stray::Extractors::RssAtom.new
    results = extractor.extract("https://example.com/feed.xml")

    assert_equal 2, results.size
    assert_equal "First Post", results[0].title
    assert_equal "https://example.com/posts/1", results[0].url
    assert_equal "https://example.com/posts/1", results[0].external_id
    assert_equal "Content of first post", results[0].content_text
    assert_nil results[0].duration
  end

  test "extract_feed delegates to extract" do
    rss_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test</title>
          <link>https://example.com</link>
          <description>Test</description>
          <item>
            <title>Post</title>
            <link>https://example.com/p1</link>
            <description>Desc</description>
            <guid>https://example.com/p1</guid>
          </item>
        </channel>
      </rss>
    XML

    stub_request(:get, "https://example.com/rss")
      .to_return(body: rss_xml, headers: { "Content-Type" => "application/rss+xml" })

    extractor = Stray::Extractors::RssAtom.new
    results = extractor.extract_feed("https://example.com/rss")
    assert_equal 1, results.size
  end

  test "extract includes creator_identity from feed metadata" do
    rss_xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Blog</title>
          <link>https://example.com</link>
          <description>Test</description>
          <item>
            <title>Post</title>
            <link>https://example.com/p1</link>
            <description>Desc</description>
            <guid>https://example.com/p1</guid>
          </item>
        </channel>
      </rss>
    XML

    stub_request(:get, "https://example.com/feed")
      .to_return(body: rss_xml, headers: { "Content-Type" => "application/rss+xml" })

    extractor = Stray::Extractors::RssAtom.new
    results = extractor.extract("https://example.com/feed")

    creator = results.first.creator_identity
    assert_equal "Test Blog", creator.name
    assert_equal "https://example.com", creator.url
  end
end
