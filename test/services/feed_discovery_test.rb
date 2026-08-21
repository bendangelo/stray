require "test_helper"

class FeedDiscoveryTest < ActiveSupport::TestCase
  test "find_feed_url returns RSS link when present in HTML head" do
    html = %(<html><head><link rel="alternate" type="application/rss+xml" href="https://example.com/feed.xml" title="RSS"></head><body></body></html>)
    result = FeedDiscovery.find_feed_url(html, "https://example.com")
    assert_equal "https://example.com/feed.xml", result
  end

  test "find_feed_url returns Atom link when present" do
    html = %(<html><head><link rel="alternate" type="application/atom+xml" href="https://example.com/atom" title="Atom"></head><body></body></html>)
    result = FeedDiscovery.find_feed_url(html, "https://example.com")
    assert_equal "https://example.com/atom", result
  end

  test "find_feed_url returns nil when no feed link present" do
    html = %(<html><head></head><body>just a page</body></html>)
    result = FeedDiscovery.find_feed_url(html, "https://example.com")
    assert_nil result
  end

  test "find_feed_url resolves relative URLs against the base URL" do
    html = %(<html><head><link rel="alternate" type="application/rss+xml" href="/blog/feed.xml"></head><body></body></html>)
    result = FeedDiscovery.find_feed_url(html, "https://example.com/blog/")
    assert_equal "https://example.com/blog/feed.xml", result
  end

  test "find_feed_url prefers RSS over Atom when both present" do
    html = %(<html><head>
      <link rel="alternate" type="application/atom+xml" href="https://example.com/atom">
      <link rel="alternate" type="application/rss+xml" href="https://example.com/rss">
    </head><body></body></html>)
    result = FeedDiscovery.find_feed_url(html, "https://example.com")
    assert_equal "https://example.com/rss", result
  end
end
