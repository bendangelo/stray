require "test_helper"

class FeedInterleaverTest < ActiveSupport::TestCase
  FakeItem = Struct.new(:id, :published_at)

  def item(id, minutes_ago)
    FakeItem.new(id, minutes_ago.minutes.ago)
  end

  test "interleave is chronological when times interleave" do
    queues = {
      1 => [ item(1, 5), item(3, 15), item(5, 25) ],
      2 => [ item(2, 10), item(4, 20), item(6, 30) ]
    }
    entries = FeedInterleaver.interleave(queues: queues, weights: { 1 => 1.0, 2 => 1.0 })
    assert_equal [ 1, 2, 3, 4, 5, 6 ], entries.map { |e| e.item.id }
  end

  test "interleave never repeats a source three times when another source has items" do
    queues = {
      1 => Array.new(4) { |i| item(i + 1, i + 1) },
      2 => Array.new(4) { |i| item(i + 10, i + 1) }
    }
    entries = FeedInterleaver.interleave(queues: queues, weights: { 1 => 1.0, 2 => 1.0 }, max_run: 2)
    sources = entries.map(&:source_id)
    assert_equal 8, sources.size
    assert sources.each_cons(3).none? { |a, b, c| a == b && b == c },
      "no source may appear three times consecutively: #{sources.inspect}"
  end

  test "max_run of 1 strictly rotates between sources" do
    queues = {
      1 => Array.new(3) { |i| item(i + 1, i + 1) },
      2 => Array.new(3) { |i| item(i + 10, i + 1) },
      3 => Array.new(3) { |i| item(i + 20, i + 1) }
    }
    entries = FeedInterleaver.interleave(queues: queues, weights: {}, max_run: 1)
    sources = entries.map(&:source_id)
    assert sources.each_cons(2).none? { |a, b| a == b }, sources.inspect
  end

  test "higher weight is served proportionally more" do
    # source 1 has 60 items (published 31-90m ago), source 2 has 30 (published 1-30m ago).
    # source 2's items are always newer, so it wins virtual-time ties; source 1's larger
    # queue keeps it from exhausting before weight has an effect. Expected split 2:1.
    queues = {
      1 => Array.new(60) { |i| item(i + 1, i + 31) },
      2 => Array.new(30) { |i| item(i + 100, i + 1) }
    }
    # Stop before either queue is exhausted (result_limit 45 of 90) so the served
    # split is decided by weight, not by queue depletion.
    entries = FeedInterleaver.interleave(
      queues: queues, weights: { 1 => 2.0, 2 => 1.0 }, result_limit: 45
    )
    counts = entries.group_by(&:source_id).transform_values(&:size)
    ratio = counts[1].to_f / counts[2]
    assert_in_delta 2.0, ratio, 0.3, "ratio was #{ratio} (#{counts.inspect})"
  end

  test "a low-weight source is never starved" do
    queues = {
      1 => Array.new(10) { |i| item(i + 1, i + 1) },
      2 => Array.new(3) { |i| item(i + 100, i + 1) }
    }
    entries = FeedInterleaver.interleave(queues: queues, weights: { 1 => 3.0, 2 => 0.1 })
    assert_operator entries.count { |e| e.source_id == 2 }, :>=, 3
  end

  test "is deterministic" do
    queues = {
      1 => Array.new(5) { |i| item(i + 1, i + 1) },
      2 => Array.new(5) { |i| item(i + 10, i + 1) }
    }
    weights = { 1 => 1.0, 2 => 1.0 }
    first = FeedInterleaver.interleave(queues: queues, weights: weights).map { |e| e.item.id }
    second = FeedInterleaver.interleave(queues: queues, weights: weights).map { |e| e.item.id }
    assert_equal first, second
  end

  test "respects result limit" do
    queues = { 1 => Array.new(10) { |i| item(i + 1, i + 1) } }
    entries = FeedInterleaver.interleave(queues: queues, weights: {}, result_limit: 4)
    assert_equal 4, entries.size
  end

  def create_item(source, published_at:, state: :unseen, title: "Item")
    Item.create!(
      source: source,
      user: source.user,
      external_id: SecureRandom.hex(8),
      title: title,
      url: "https://example.com/#{SecureRandom.hex(8)}",
      content_text: "x",
      published_at: published_at,
      state: state
    )
  end

  test "call returns entries only for unseen items" do
    user = users(:one)
    source = sources(:youtube)
    create_item(source, published_at: 1.hour.ago, title: "Unseen A")
    create_item(source, published_at: 2.hours.ago, state: :seen, title: "Seen B")
    create_item(source, published_at: 3.hours.ago, state: :saved, title: "Saved C")
    create_item(source, published_at: 4.hours.ago, state: :hidden, title: "Hidden D")

    entries = FeedInterleaver.call(user: user)

    titles = entries.map { |e| e.item.title }
    assert_includes titles, "Unseen A"
    assert_not_includes titles, "Seen B"
    assert_not_includes titles, "Saved C"
    assert_not_includes titles, "Hidden D"
  end

  test "call excludes muted sources unless show_muted" do
    user = users(:one)
    source = sources(:bitchute)
    follows(:two).update!(muted: true)
    create_item(source, published_at: 1.hour.ago, title: "Muted Item")

    assert_empty FeedInterleaver.call(user: user).select { |e| e.source_id == source.id }
    refute_empty FeedInterleaver.call(user: user, show_muted: true).select { |e| e.source_id == source.id }
  end

  test "call caps each source at the per-source window" do
    user = users(:one)
    source = sources(:youtube)
    35.times { |i| create_item(source, published_at: i.minutes.ago, title: "Bulk #{i}") }

    entries = FeedInterleaver.call(user: user, window_per_source: 30)

    assert_equal 30, entries.count { |e| e.source_id == source.id }
  end

  test "include_items forces a seen item into the mix" do
    user = users(:one)
    item = items(:video_one)
    item.update!(state: :seen)

    entries = FeedInterleaver.call(user: user, include_items: [ item ])

    assert_includes entries.map { |e| e.item.id }, item.id
  end

  test "include_items ignores hidden items" do
    user = users(:one)
    item = items(:video_hidden)

    entries = FeedInterleaver.call(user: user, include_items: [ item ])

    assert_not_includes entries.map { |e| e.item.id }, item.id
  end

  test "call returns empty for a user with no follows" do
    assert_empty FeedInterleaver.call(user: users(:two).tap { |u| u.follows.destroy_all })
  end

  test "source_position numbers each source's served items from 1" do
    user = users(:one)
    source = sources(:youtube)
    create_item(source, published_at: 1.hour.ago, title: "P1")
    create_item(source, published_at: 2.hours.ago, title: "P2")

    entries = FeedInterleaver.call(user: user, show_muted: true)
                 .select { |e| e.source_id == source.id }

    assert_equal (1..entries.size).to_a, entries.map(&:source_position)
  end
end
