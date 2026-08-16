require "test_helper"

class SourceTest < ActiveSupport::TestCase
  test "valid source with required attributes" do
    source = Source.new(
      user: users(:one),
      kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCtest123",
      external_id: "UCtest123"
    )
    assert source.valid?
  end

  test "invalid without url" do
    source = Source.new(user: users(:one), kind: :youtube_channel)
    assert_not source.valid?
    assert_includes source.errors[:url], "can't be blank"
  end

  test "invalid without kind" do
    source = Source.new(user: users(:one), url: "https://example.com")
    assert_not source.valid?
    assert_includes source.errors[:kind], "can't be blank"
  end

  test "external_id unique per user and kind" do
    Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC123")
    duplicate = Source.new(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed2", external_id: "UC123")
    assert_not duplicate.valid?
  end

  test "same external_id allowed for different user" do
    Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC123")
    other = Source.new(user: users(:two), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC123")
    assert other.valid?
  end

  test "due_for_poll scope returns active sources with past or null next_crawl_at" do
    due = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com", external_id: "UC1", next_crawl_at: 1.hour.ago)
    not_due = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/2", external_id: "UC2", next_crawl_at: 1.hour.from_now)
    inactive = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/3", external_id: "UC3", next_crawl_at: 1.hour.ago, active: false)
    null_crawl = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/4", external_id: "UC4", next_crawl_at: nil)

    result = Source.due_for_poll.to_a
    assert_includes result, due
    assert_includes result, null_crawl
    assert_not_includes result, not_due
    assert_not_includes result, inactive
  end

  test "recalculate_next_crawl! sets 1 hour from now when no items" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com", external_id: "UC1")
    source.recalculate_next_crawl!
    assert_in_delta 1.hour.from_now, source.next_crawl_at, 5.seconds
  end

  test "recalculate_next_crawl! predicts from average interval of recent items" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com", external_id: "UC1")
    now = Time.current
    source.items.create!(user: users(:one), external_id: "v1", title: "V1", url: "https://example.com/v1", published_at: now - 4.days)
    source.items.create!(user: users(:one), external_id: "v2", title: "V2", url: "https://example.com/v2", published_at: now - 3.days)
    source.items.create!(user: users(:one), external_id: "v3", title: "V3", url: "https://example.com/v3", published_at: now - 2.days)
    source.items.create!(user: users(:one), external_id: "v4", title: "V4", url: "https://example.com/v4", published_at: now - 1.day)

    source.recalculate_next_crawl!
    # avg interval = 1 day, last published = now - 1.day, predicted = now,
    # but the min cap of 30 minutes from now applies
    assert_in_delta 30.minutes.from_now, source.next_crawl_at, 5.seconds
  end

  test "recalculate_next_crawl! caps at 24 hours max" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com", external_id: "UC1")
    now = Time.current
    source.items.create!(user: users(:one), external_id: "v1", title: "V1", url: "https://example.com/v1", published_at: now - 1.hour)
    source.items.create!(user: users(:one), external_id: "v2", title: "V2", url: "https://example.com/v2", published_at: now - 30.minutes)

    source.recalculate_next_crawl!
    # avg interval = 30min, last = now-30min, predicted = now. But cap min is 30min from now.
    assert source.next_crawl_at <= 30.minutes.from_now + 5.seconds
  end

  test "recalculate_next_crawl! pauses dead sources" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com", external_id: "UC1")
    source.items.create!(user: users(:one), external_id: "v1", title: "V1", url: "https://example.com/v1", published_at: 2.years.ago)

    source.recalculate_next_crawl!
    assert_not source.active
  end

  test "active scope returns only active sources" do
    assert_includes Source.active, sources(:youtube)
    assert_not_includes Source.active, sources(:inactive)
  end

  test "inactive scope returns only inactive sources" do
    assert_includes Source.inactive, sources(:inactive)
    assert_not_includes Source.inactive, sources(:youtube)
  end

  test "search with blank q returns all sources" do
    assert_includes Source.matching(nil), sources(:youtube)
    assert_includes Source.matching(""), sources(:youtube)
  end

  test "search with q matching name returns matching source" do
    result = Source.matching("Test Channel")
    assert_includes result, sources(:youtube)
    assert_not_includes result, sources(:bitchute)
  end

  test "search with q matching url returns matching source" do
    result = Source.matching("bitchute")
    assert_includes result, sources(:bitchute)
    assert_not_includes result, sources(:youtube)
  end

  test "search with q matching nothing returns empty" do
    assert_empty Source.matching("nonexistent-source-xyz")
  end
end
