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
end
