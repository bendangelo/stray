require "test_helper"

class RankingTest < ActiveSupport::TestCase
  test "clamp clamps weight to [0.1, 3.0]" do
    assert_equal 0.1, Ranking.clamp(0.0)
    assert_equal 3.0, Ranking.clamp(5.0)
    assert_equal 1.5, Ranking.clamp(1.5)
  end

  test "order_sql returns effective_time DESC with tiebreaker" do
    sql = Ranking.order_sql
    assert_includes sql, "datetime(items.published_at, printf('%+.1f hours', (follows.weight - 1.0) * 24)) DESC"
    assert_includes sql, "items.published_at DESC"
  end

  test "muted_enough returns true when 3+ hidden interactions in window" do
    user = users(:one)
    source = sources(:youtube)
    3.times do |i|
      item = source.items.create!(
        user: user, external_id: "mute-#{i}", title: "Mute #{i}",
        url: "https://example.com/#{i}", content_text: "x",
        published_at: 1.day.ago, state: 0
      )
      Interaction.create!(user: user, item: item, kind: :hidden)
    end
    assert Ranking.muted_enough?(user: user, source_id: source.id)
  end

  test "muted_enough returns false when fewer than 3 hidden interactions" do
    user = users(:one)
    source = sources(:youtube)
    item = source.items.create!(
      user: user, external_id: "mute-1", title: "Mute 1",
      url: "https://example.com/1", content_text: "x",
      published_at: 1.day.ago, state: 0
    )
    Interaction.create!(user: user, item: item, kind: :hidden)
    assert_not Ranking.muted_enough?(user: user, source_id: source.id)
  end

  test "muted_enough ignores interactions outside the 7-day window" do
    user = users(:one)
    source = sources(:youtube)
    3.times do |i|
      item = source.items.create!(
        user: user, external_id: "old-mute-#{i}", title: "Old Mute #{i}",
        url: "https://example.com/old-#{i}", content_text: "x",
        published_at: 10.days.ago, state: 0
      )
      interaction = Interaction.create!(user: user, item: item, kind: :hidden)
      interaction.update_column(:created_at, 10.days.ago)
    end
    assert_not Ranking.muted_enough?(user: user, source_id: source.id)
  end

  test "apply_interaction nudges weight up for opened" do
    user = users(:one)
    source = sources(:bitchute)
    follow = follows(:two)
    assert_equal 0.5, follow.weight
    item = source.items.create!(
      user: user, external_id: "open-1", title: "Open 1",
      url: "https://example.com/open-1", content_text: "x",
      published_at: 1.hour.ago, state: 0
    )
    Ranking.apply_interaction!(user: user, item: item, kind: :opened)
    follow.reload
    assert_in_delta 0.55, follow.weight, 0.001
  end

  test "apply_interaction nudges weight down for hidden" do
    user = users(:one)
    source = sources(:youtube)
    follow = follows(:one)
    assert_equal 1.0, follow.weight
    item = source.items.first
    Ranking.apply_interaction!(user: user, item: item, kind: :hidden)
    follow.reload
    assert_in_delta 0.9, follow.weight, 0.001
  end

  test "apply_interaction is idempotent — second open does not nudge again" do
    user = users(:one)
    source = sources(:youtube)
    follow = follows(:one)
    item = source.items.first
    Ranking.apply_interaction!(user: user, item: item, kind: :opened)
    first_weight = follow.reload.weight
    Ranking.apply_interaction!(user: user, item: item, kind: :opened)
    follow.reload
    assert_equal first_weight, follow.weight
  end

  test "apply_interaction with nil kind is a no-op" do
    user = users(:one)
    source = sources(:youtube)
    follow = follows(:one)
    item = source.items.first
    Ranking.apply_interaction!(user: user, item: item, kind: nil)
    follow.reload
    assert_equal 1.0, follow.weight
  end

  test "apply_interaction sets muted when 3+ hides in window" do
    user = users(:one)
    source = sources(:youtube)
    follow = follows(:one)
    2.times do |i|
      item = source.items.create!(
        user: user, external_id: "m-#{i}", title: "M #{i}",
        url: "https://example.com/m-#{i}", content_text: "x",
        published_at: 1.day.ago, state: 0
      )
      Ranking.apply_interaction!(user: user, item: item, kind: :hidden)
    end
    follow.reload
    assert_not follow.muted

    third = source.items.create!(
      user: user, external_id: "m-3", title: "M 3",
      url: "https://example.com/m-3", content_text: "x",
      published_at: 1.day.ago, state: 0
    )
    Ranking.apply_interaction!(user: user, item: third, kind: :hidden)
    follow.reload
    assert follow.muted
  end
end
