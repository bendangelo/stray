require "test_helper"

class TaggingTest < ActiveSupport::TestCase
  test "valid tagging" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    item = Item.create!(source:, user: users(:one), external_id: "v1", title: "A", url: "https://example.com/a")
    tag = Tag.create!(user: users(:one), name: "ruby")
    tagging = Tagging.new(item:, tag:, source: :user)
    assert tagging.valid?
  end

  test "tag unique per item and source type" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    item = Item.create!(source:, user: users(:one), external_id: "v1", title: "A", url: "https://example.com/a")
    tag = Tag.create!(user: users(:one), name: "ruby")
    Tagging.create!(item:, tag:, source: :user)
    duplicate = Tagging.new(item:, tag:, source: :user)
    assert_not duplicate.valid?
  end

  test "same tag allowed with different source type" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    item = Item.create!(source:, user: users(:one), external_id: "v1", title: "A", url: "https://example.com/a")
    tag = Tag.create!(user: users(:one), name: "ruby")
    Tagging.create!(item:, tag:, source: :user)
    other = Tagging.new(item:, tag:, source: :ai_embedding)
    assert other.valid?
  end
end
