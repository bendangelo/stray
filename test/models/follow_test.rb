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
end
