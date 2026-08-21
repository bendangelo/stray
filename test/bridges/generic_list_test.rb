require "test_helper"

class Bridges::GenericListTest < ActiveSupport::TestCase
  test "handles_kind? returns true for generic_list" do
    assert Bridges::GenericList.handles_kind?("generic_list")
  end

  test "handles_kind? returns false for other kinds" do
    assert_not Bridges::GenericList.handles_kind?("generic_page")
    assert_not Bridges::GenericList.handles_kind?("rss_feed")
  end

  test "matches? returns true for any http/https URL" do
    assert Bridges::GenericList.matches?("https://example.com/blog")
    assert Bridges::GenericList.matches?("http://example.com")
  end

  test "trust_level is :scraped_html" do
    assert_equal :scraped_html, Bridges::GenericList.trust_level
  end

  test "detect returns item count when JSON-LD ItemList is present" do
    html = %(<html><head>
      <script type="application/ld+json">
      {"@type":"ItemList","itemListElement":[
        {"@type":"ListItem","position":1,"url":"https://example.com/post-1","name":"Post 1"},
        {"@type":"ListItem","position":2,"url":"https://example.com/post-2","name":"Post 2"},
        {"@type":"ListItem","position":3,"url":"https://example.com/post-3","name":"Post 3"}
      ]}
      </script>
    </head><body></body></html>)
    assert_equal 3, Bridges::GenericList.detect(html)
  end

  test "detect returns nil when no list structure found" do
    html = %(<html><head></head><body><p>Just a single article page with no list.</p></body></html>)
    assert_nil Bridges::GenericList.detect(html)
  end

  test "extract_feed parses JSON-LD ItemList into ExtractedContent array" do
    html = %(<html><head>
      <script type="application/ld+json">
      {"@type":"ItemList","itemListElement":[
        {"@type":"ListItem","position":1,"url":"https://example.com/post-1","name":"Post 1","image":"https://example.com/img1.jpg","datePublished":"2025-01-01T00:00:00Z"},
        {"@type":"ListItem","position":2,"url":"https://example.com/post-2","name":"Post 2","image":"https://example.com/img2.jpg","datePublished":"2025-01-02T00:00:00Z"}
      ]}
      </script>
    </head><body></body></html>)
    PoliteCrawl.stub(:sleep, -> {}) do
      bridge = Bridges::GenericList.new
      results = bridge.extract_feed_from_html(html, "https://example.com")
      assert_equal 2, results.size
      assert_equal "Post 1", results[0].title
      assert_equal "https://example.com/post-1", results[0].url
      assert_equal "https://example.com/img1.jpg", results[0].thumbnail_url
      assert_equal Digest::SHA256.hexdigest("https://example.com/post-1"), results[0].external_id
    end
  end
end
