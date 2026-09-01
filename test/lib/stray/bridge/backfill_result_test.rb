require "test_helper"

class Stray::Bridge::BackfillResultTest < ActiveSupport::TestCase
  test "has items, next_cursor, has_more" do
    item = Stray::ExtractedContent.new(url: "https://x", title: "T", content_text: nil,
      content_html: nil, thumbnail_url: nil, published_at: nil, external_id: "x",
      duration: nil, creator_identity: nil, tags: [])
    result = Stray::Bridge::BackfillResult.new(items: [ item ], next_cursor: 2, has_more: true)
    assert_equal [ item ], result.items
    assert_equal 2, result.next_cursor
    assert result.has_more
  end

  test "has_more defaults to false" do
    result = Stray::Bridge::BackfillResult.new(items: [], next_cursor: nil)
    assert_not result.has_more
  end
end
