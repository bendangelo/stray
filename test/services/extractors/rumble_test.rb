require "test_helper"

class Extractors::RumbleTest < ActiveSupport::TestCase
  test "matches? delegates to core" do
    assert Extractors::Rumble.matches?("https://rumble.com/c/Foo")
    assert_not Extractors::Rumble.matches?("https://example.com")
  end

  test "handles_kind? returns true for rumble_channel" do
    assert Extractors::Rumble.handles_kind?("rumble_channel")
    assert_not Extractors::Rumble.handles_kind?("rss_feed")
  end

  test "extract_feed maps core hashes to ExtractedContent" do
    core = Minitest::Mock.new
    core.expect(:channel_feed, [ {
      url: "https://rumble.com/vabc", title: "Video", external_id: "123",
      duration: 100, published_at: Time.now, thumbnail_url: "https://img.jpg",
      tags: [ "a" ], views: 5, live: false, is_short: false,
      creator_identity: { name: "Chan", url: "https://rumble.com/c/C", external_id: "c1", thumbnail_url: nil }
    } ], [ "https://rumble.com/c/C" ])

    Stray::Extractors::Rumble.stub(:new, core) do
      result = Extractors::Rumble.new.extract_feed("https://rumble.com/c/C")
      assert_equal 1, result.size
      content = result.first
      assert_equal "123", content.external_id
      assert_equal "Chan", content.creator_identity.name
    end
  end

  test "extract maps a single video page" do
    core = Minitest::Mock.new
    core.expect(:video_page, {
      url: "https://rumble.com/vabc", title: "Video", external_id: "123",
      duration: 100, published_at: nil, thumbnail_url: "https://img.jpg",
      tags: [], views: nil, live: nil, is_short: nil, creator_identity: nil
    }, [ "https://rumble.com/vabc" ])

    Stray::Extractors::Rumble.stub(:new, core) do
      content = Extractors::Rumble.new.extract("https://rumble.com/vabc")
      assert_equal "123", content.external_id
      assert_nil content.creator_identity
    end
  end
end
