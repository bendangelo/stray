require "test_helper"

class Extractor::FeedResultTest < ActiveSupport::TestCase
  test "has items, next_cursor, has_more" do
    item = ExtractedContent.new(url: "https://x", title: "T", content_text: nil,
      content_html: nil, thumbnail_url: nil, published_at: nil, external_id: "x",
      duration: nil, creator_identity: nil, tags: [])
    result = Extractor::FeedResult.new(items: [ item ], next_cursor: "cur", has_more: true)
    assert_equal [ item ], result.items
    assert_equal "cur", result.next_cursor
    assert result.has_more
  end

  test "has_more defaults to false" do
    result = Extractor::FeedResult.new(items: [], next_cursor: nil)
    assert_not result.has_more
  end
end
