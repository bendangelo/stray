require "test_helper"

class ItemTest < ActiveSupport::TestCase
  test "valid item with required attributes" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    item = Item.new(source:, user: users(:one), external_id: "vid1", title: "Test Video", url: "https://example.com/v1")
    assert item.valid?
  end

  test "invalid without title" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    item = Item.new(source:, user: users(:one), external_id: "vid1", url: "https://example.com/v1")
    assert_not item.valid?
    assert_includes item.errors[:title], "can't be blank"
  end

  test "external_id unique per source" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    Item.create!(source:, user: users(:one), external_id: "vid1", title: "A", url: "https://example.com/a")
    duplicate = Item.new(source:, user: users(:one), external_id: "vid1", title: "B", url: "https://example.com/b")
    assert_not duplicate.valid?
  end

  test "same external_id allowed for different source" do
    s1 = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/1", external_id: "UC1")
    s2 = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/2", external_id: "UC2")
    Item.create!(source: s1, user: users(:one), external_id: "vid1", title: "A", url: "https://example.com/a")
    other = Item.new(source: s2, user: users(:one), external_id: "vid1", title: "B", url: "https://example.com/b")
    assert other.valid?
  end

  test "default state is unseen" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    item = Item.create!(source:, user: users(:one), external_id: "vid1", title: "A", url: "https://example.com/a")
    assert item.unseen?
  end

  test "state transitions" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    item = Item.create!(source:, user: users(:one), external_id: "vid1", title: "A", url: "https://example.com/a")
    item.seen!
    assert item.seen?
    item.saved!
    assert item.saved?
    item.hidden!
    assert item.hidden?
  end

  test "full_search finds by title" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    Item.create!(source:, user: users(:one), external_id: "v1", title: "Ruby on Rails Tutorial", url: "https://example.com/v1", content_text: "Learn web development")
    Item.create!(source:, user: users(:one), external_id: "v2", title: "Cooking Pasta", url: "https://example.com/v2", content_text: "Italian recipes")

    results = Item.search("ruby rails")
    assert_includes results.map(&:title), "Ruby on Rails Tutorial"
    assert_not_includes results.map(&:title), "Cooking Pasta"
  end

  test "unseen scope returns only unseen items" do
    unseen = Item.unseen.to_a
    assert_includes unseen, items(:video_one)
    assert_not_includes unseen, items(:video_saved)
    assert_not_includes unseen, items(:video_hidden)
  end
end
