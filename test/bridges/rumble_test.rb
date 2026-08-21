require "test_helper"

class Bridges::RumbleTest < ActiveSupport::TestCase
  test "matches? delegates to core" do
    assert Bridges::Rumble.matches?("https://rumble.com/c/Foo")
    assert_not Bridges::Rumble.matches?("https://example.com")
  end

  test "handles_kind? returns true for rumble_channel" do
    assert Bridges::Rumble.handles_kind?("rumble_channel")
    assert_not Bridges::Rumble.handles_kind?("rss_feed")
  end

  test "extract_feed maps core hashes to ExtractedContent" do
    core = Minitest::Mock.new
    core.expect(:channel_feed, [ {
      url: "https://rumble.com/vabc", title: "Video", external_id: "123",
      duration: 100, published_at: Time.now, thumbnail_url: "https://img.jpg",
      tags: [ "a" ], views: 5, live: false, is_short: false,
      creator_identity: { name: "Chan", url: "https://rumble.com/c/C", external_id: "c1", thumbnail_url: nil }
    } ], [ "https://rumble.com/c/C" ])

    Stray::Bridges::Rumble.stub(:new, core) do
      result = Bridges::Rumble.new.extract_feed("https://rumble.com/c/C")
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

    Stray::Bridges::Rumble.stub(:new, core) do
      content = Bridges::Rumble.new.extract("https://rumble.com/vabc")
      assert_equal "123", content.external_id
      assert_nil content.creator_identity
    end
  end

  test "extract_backfill loops pages until limit is reached" do
    page1 = [ { url: "https://rumble.com/v1", title: "V1", external_id: "1", duration: 10, published_at: Time.now, thumbnail_url: "https://img1.jpg", tags: [], views: 1, live: false, is_short: false, creator_identity: nil },
              { url: "https://rumble.com/v2", title: "V2", external_id: "2", duration: 10, published_at: Time.now, thumbnail_url: "https://img2.jpg", tags: [], views: 1, live: false, is_short: false, creator_identity: nil } ]
    page2 = [ { url: "https://rumble.com/v3", title: "V3", external_id: "3", duration: 10, published_at: Time.now, thumbnail_url: "https://img3.jpg", tags: [], views: 1, live: false, is_short: false, creator_identity: nil } ]
    pages = [ page1, page2, [] ]
    requested = []

    core = Stray::Bridges::Rumble.new
    core.define_singleton_method(:channel_feed) do |url|
      requested << url
      pages.shift
    end
    Stray::Bridges::Rumble.stub(:new, core) do
      @results = Bridges::Rumble.new.extract_backfill("https://rumble.com/c/Foo", limit: 3)
    end

    assert_equal 3, @results.size
    assert_equal 2, requested.size
    assert_includes requested[0], "page=1"
    assert_includes requested[1], "page=2"
  end

  test "extract_backfill stops at empty page" do
    pages = [ [ { url: "https://rumble.com/v1", title: "V1", external_id: "1", duration: 10, published_at: Time.now, thumbnail_url: "https://img1.jpg", tags: [], views: 1, live: false, is_short: false, creator_identity: nil } ], [] ]
    core = Stray::Bridges::Rumble.new
    core.define_singleton_method(:channel_feed) { |_url| pages.shift }
    Stray::Bridges::Rumble.stub(:new, core) do
      @results = Bridges::Rumble.new.extract_backfill("https://rumble.com/c/Foo", limit: 50)
    end

    assert_equal 1, @results.size
  end
end
