require "test_helper"

class FeedItemPayloadTest < ActiveSupport::TestCase
  setup do
    @mod = FeedItemPayload
    @item = items(:video_one)
  end

  test "payload includes required fields" do
    @item.update!(content_html: "<p>hello</p>")
    payload = @mod.payload(@item)
    assert_equal @item.external_id, payload[:external_id]
    assert_equal @item.title, payload[:title]
    assert_equal @item.url, payload[:url]
    assert_equal @item.content_text, payload[:content_text]
    assert_equal @item.content_html, payload[:content_html]
    assert_equal @item.thumbnail_url, payload[:thumbnail_url]
    assert_equal @item.published_at&.iso8601, payload[:published_at]
    assert_equal @item.duration, payload[:duration]
    assert_equal [ "rails", "ruby" ], payload[:tags]
  end

  test "payload excludes summary, embedding, state" do
    @item.update!(summary: "secret")
    payload = @mod.payload(@item)
    assert_not payload.key?(:summary)
    assert_not payload.key?(:embedding)
    assert_not payload.key?(:state)
  end

  test "payload includes tag names from taggings" do
    tag = Tag.create!(user: users(:one), name: "unique-tag")
    Tagging.create!(item: @item, tag: tag, source: :user)
    payload = @mod.payload(@item)
    assert_equal [ "rails", "ruby", "unique-tag" ], payload[:tags]
  end

  test "published_at is iso8601 string when present, nil when absent" do
    @item.update!(published_at: nil)
    assert_nil @mod.payload(@item)[:published_at]
  end
end
