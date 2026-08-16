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

  test "suggest returns matching titles with highlights" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    Follow.create!(user: users(:one), source: source, weight: 1.0)
    Item.create!(source:, user: users(:one), external_id: "v1", title: "Ruby on Rails Tutorial", url: "https://example.com/v1", content_text: "Learn web development")
    Item.create!(source:, user: users(:one), external_id: "v2", title: "Ruby tips and tricks", url: "https://example.com/v2", content_text: "Advanced Ruby")
    Item.create!(source:, user: users(:one), external_id: "v3", title: "Cooking Pasta", url: "https://example.com/v3", content_text: "Italian recipes")

    rebuild_full_search_index(Item)

    result = Item.suggest(user: users(:one), query: "ruby", limit: 8)

    assert_equal 2, result[:items].length
    titles = result[:items].map(&:title)
    assert_includes titles, "Ruby on Rails Tutorial"
    assert_includes titles, "Ruby tips and tricks"
    assert_not_includes titles, "Cooking Pasta"

    first_item = result[:items].find { |i| i.title == "Ruby on Rails Tutorial" }
    assert_includes first_item.highlighted_title, "<mark>"
    assert_includes first_item.highlighted_title, "</mark>"
  end

  test "suggest scopes to user's followed sources" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    Follow.create!(user: users(:one), source: source, weight: 1.0)
    Item.create!(source:, user: users(:one), external_id: "v1", title: "Ruby Tutorial", url: "https://example.com/v1", content_text: "Learn Ruby")

    source_two = Source.create!(user: users(:two), kind: :youtube_channel, url: "https://example.com/feed2", external_id: "UC2")
    Follow.create!(user: users(:two), source: source_two, weight: 1.0)
    Item.create!(source: source_two, user: users(:two), external_id: "v2", title: "Ruby Secrets", url: "https://example.com/v2", content_text: "Hidden Ruby")

    rebuild_full_search_index(Item)

    result = Item.suggest(user: users(:one), query: "ruby", limit: 8)
    titles = result[:items].map(&:title)
    assert_includes titles, "Ruby Tutorial"
    assert_not_includes titles, "Ruby Secrets"
  end

  test "suggest excludes hidden items" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    Follow.create!(user: users(:one), source: source, weight: 1.0)
    Item.create!(source:, user: users(:one), external_id: "v1", title: "Ruby Tutorial", url: "https://example.com/v1", content_text: "Learn Ruby")
    Item.create!(source:, user: users(:one), external_id: "v2", title: "Ruby Hidden", url: "https://example.com/v2", content_text: "Hidden Ruby", state: :hidden)

    rebuild_full_search_index(Item)

    result = Item.suggest(user: users(:one), query: "ruby", limit: 8)
    titles = result[:items].map(&:title)
    assert_includes titles, "Ruby Tutorial"
    assert_not_includes titles, "Ruby Hidden"
  end

  test "suggest respects limit" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    Follow.create!(user: users(:one), source: source, weight: 1.0)
    5.times do |i|
      Item.create!(source:, user: users(:one), external_id: "v#{i}", title: "Ruby Post #{i}", url: "https://example.com/v#{i}", content_text: "Ruby content")
    end

    rebuild_full_search_index(Item)

    result = Item.suggest(user: users(:one), query: "ruby", limit: 3)
    assert_equal 3, result[:items].length
  end

  test "suggest returns term hints from matching titles" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    Follow.create!(user: users(:one), source: source, weight: 1.0)
    Item.create!(source:, user: users(:one), external_id: "v1", title: "Ruby on Rails Tutorial", url: "https://example.com/v1", content_text: "Learn web development")
    Item.create!(source:, user: users(:one), external_id: "v2", title: "Rubyists guide to programming", url: "https://example.com/v2", content_text: "Advanced")

    rebuild_full_search_index(Item)

    result = Item.suggest(user: users(:one), query: "rub", limit: 8)
    assert result[:term_hints].is_a?(Array)
    assert_includes result[:term_hints], "ruby"
    assert_includes result[:term_hints], "rubyists"
  end

  test "suggest returns empty for short query" do
    result = Item.suggest(user: users(:one), query: "ru", limit: 8)
    assert_empty result[:items]
    assert_empty result[:term_hints]
  end

  test "suggest returns empty on FTS error" do
    result = Item.suggest(user: users(:one), query: '"', limit: 8)
    assert_empty result[:items]
    assert_empty result[:term_hints]
  end
end
