require "test_helper"

class Extractor::FeedResultTest < ActiveSupport::TestCase
  test "has items, next_cursor, has_more" do
    item = Stray::ExtractedContent.new(url: "https://x", title: "T", content_text: nil,
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

  test "collection metadata defaults to nil" do
    result = Extractor::FeedResult.new(items: [], next_cursor: nil)
    assert_nil result.collection_name
    assert_nil result.producer_instance_name
  end

  test "collection metadata can be set" do
    result = Extractor::FeedResult.new(items: [], next_cursor: nil, collection_name: "Econ", producer_instance_name: "Alice")
    assert_equal "Econ", result.collection_name
    assert_equal "Alice", result.producer_instance_name
  end
end
