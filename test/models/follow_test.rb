require "test_helper"

class FollowTest < ActiveSupport::TestCase
  test "valid follow" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    follow = Follow.new(user: users(:one), source:)
    assert follow.valid?
  end

  test "unique per user and source" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    Follow.create!(user: users(:one), source:)
    duplicate = Follow.new(user: users(:one), source:)
    assert_not duplicate.valid?
  end

  test "default weight is 1.0" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed", external_id: "UC1")
    follow = Follow.create!(user: users(:one), source:)
    assert_equal 1.0, follow.weight
  end

  test "default muted is false" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed2", external_id: "UC2")
    follow = Follow.create!(user: users(:one), source:)
    assert_not follow.muted
  end

  test "clamp_weight clamps on save when above max" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed3", external_id: "UC3")
    follow = Follow.create!(user: users(:one), source:, weight: 10.0)
    assert_equal 3.0, follow.weight
  end

  test "clamp_weight clamps on save when below min" do
    source = Source.create!(user: users(:one), kind: :youtube_channel, url: "https://example.com/feed4", external_id: "UC4")
    follow = Follow.create!(user: users(:one), source:, weight: 0.0)
    assert_equal 0.1, follow.weight
  end
end
