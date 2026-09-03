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
      url: "https://rumble.com/vabc", title: "Video", external_id: "123", embed_id: "vabc",
      duration: 100, published_at: Time.now, thumbnail_url: "https://img.jpg",
      tags: [ "a" ], views: 5, live: false, is_short: false,
      creator_identity: { name: "Chan", url: "https://rumble.com/c/C", external_id: "c1", thumbnail_url: nil }
    } ], [ "https://rumble.com/c/C" ])

    Stray::Bridges::Rumble.stub(:new, core) do
      result = Bridges::Rumble.new.extract_feed("https://rumble.com/c/C")
      assert_equal 1, result.size
      content = result.first
      assert_equal "123", content.external_id
      assert_equal "vabc", content.embed_id
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

  test "extract_backfill fetches a single page and returns BackfillResult" do
    item = {
      url: "https://rumble.com/v1", title: "V1", external_id: "1", duration: 10,
      published_at: Time.now, thumbnail_url: "https://img1.jpg", tags: [], views: 1,
      live: false, is_short: false, creator_identity: nil
    }
    core = Stray::Bridges::Rumble.new
    requested_url = nil
    core.define_singleton_method(:channel_feed) do |url|
      requested_url = url
      [ item ]
    end
    Stray::Bridges::Rumble.stub(:new, core) do
      result = Bridges::Rumble.new.extract_backfill("https://rumble.com/c/Foo", limit: 50, cursor: 2)
      assert result.is_a?(Stray::Bridge::BackfillResult)
      assert_equal 1, result.items.size
      assert_equal "1", result.items.first.external_id
      assert_equal 3, result.next_cursor
      assert result.has_more
    end
    assert_includes requested_url, "page=2"
  end

  test "extract_backfill reports has_more true on a full page" do
    items = (1..3).map do |i|
      {
        url: "https://rumble.com/v#{i}", title: "V#{i}", external_id: i.to_s, duration: 10,
        published_at: Time.now, thumbnail_url: "https://img#{i}.jpg", tags: [], views: 1,
        live: false, is_short: false, creator_identity: nil
      }
    end
    core = Stray::Bridges::Rumble.new
    core.define_singleton_method(:channel_feed) { |_url| items }
    Stray::Bridges::Rumble.stub(:new, core) do
      result = Bridges::Rumble.new.extract_backfill("https://rumble.com/c/Foo", limit: 3, cursor: 1)
      assert result.is_a?(Stray::Bridge::BackfillResult)
      assert_equal 3, result.items.size
      assert_equal 2, result.next_cursor
      assert result.has_more
    end
  end

  test "extract_backfill stops when a page is empty" do
    core = Stray::Bridges::Rumble.new
    core.define_singleton_method(:channel_feed) { |_url| [] }
    Stray::Bridges::Rumble.stub(:new, core) do
      result = Bridges::Rumble.new.extract_backfill("https://rumble.com/c/Foo", limit: 50, cursor: 2)
      assert result.is_a?(Stray::Bridge::BackfillResult)
      assert_empty result.items
      assert_nil result.next_cursor
      assert_not result.has_more
    end
  end

  test "extract_feed_from_response maps a pre-fetched channel body" do
    core = Minitest::Mock.new
    core.expect(:feed_from_html, [ {
      url: "https://rumble.com/vabc", title: "Video", external_id: "123",
      duration: 100, published_at: Time.now, thumbnail_url: "https://img.jpg",
      tags: [ "a" ], views: 5, live: false, is_short: false,
      creator_identity: { name: "Chan", url: "https://rumble.com/c/C", external_id: "c1", thumbnail_url: nil }
    } ], [ "body", "https://rumble.com/c/C" ])

    response = Struct.new(:status, :body, :headers).new(200, "body", {})

    Stray::Bridges::Rumble.stub(:new, core) do
      result = Bridges::Rumble.new.extract_feed_from_response(response, "https://rumble.com/c/C")
      assert_equal 1, result.size
      assert_equal "123", result.first.external_id
      assert_equal "Chan", result.first.creator_identity.name
    end
  end
end
