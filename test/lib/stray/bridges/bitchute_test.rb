require "test_helper"
require "ostruct"
require "json"

class Stray::Bridges::BitchuteTest < ActiveSupport::TestCase
  SAMPLE_VIDEO = {
    "video_id" => "UA8c4dHy7zI",
    "video_name" => "Video One",
    "video_url" => "/video/UA8c4dHy7zI/",
    "date_published" => "2026-09-07T08:25:20Z",
    "description" => "desc one",
    "duration" => "15:10",
    "thumbnail_url" => "https://static-3.bitchute.com/live/cover_images/C1/UA8c4dHy7zI_640x360.jpg",
    "view_count" => 609
  }.freeze

  SAMPLE_VIDEO_DETAIL = {
    "video_id" => "UA8c4dHy7zI",
    "video_name" => "Video One",
    "description" => "desc one",
    "hashtags" => %w[politics news],
    "date_published" => "2026-09-07T08:25:20Z",
    "duration" => "15:10",
    "thumbnail_url" => "https://static-3.bitchute.com/live/cover_images/C1/UA8c4dHy7zI_640x360.jpg",
    "view_count" => 609,
    "channel" => {
      "channel_id" => "C1",
      "channel_name" => "Stew Peters",
      "channel_url" => "/channel/C1/",
      "thumbnail_url" => "https://static-3.bitchute.com/live/channel_images/C1/banner.jpg"
    }
  }.freeze

  test "matches? returns true for bitchute URLs" do
    assert Stray::Bridges::Bitchute.matches?("https://www.bitchute.com/channel/Foo")
    assert Stray::Bridges::Bitchute.matches?("https://www.bitchute.com/video/abc123")
  end

  test "matches? returns false for non-bitchute URLs" do
    assert_not Stray::Bridges::Bitchute.matches?("https://example.com")
  end

  test "channel_id and video_id parse paths" do
    assert_equal "Foo", Stray::Bridges::Bitchute.channel_id("https://www.bitchute.com/channel/Foo")
    assert_equal "abc123", Stray::Bridges::Bitchute.video_id("https://www.bitchute.com/video/abc123")
  end

  test "channel_feed posts to the channel videos API and normalizes" do
    captured = nil
    PoliteCrawl.stub(:post, lambda { |url, **opts| captured = [ url, opts[:json] ]; OpenStruct.new(status: 200, body: { "videos" => [ SAMPLE_VIDEO ] }.to_json) }) do
      items = Stray::Bridges::Bitchute.new.channel_feed("https://www.bitchute.com/channel/C1")

      assert_equal 1, items.size
      first = items.first
      assert_equal "UA8c4dHy7zI", first[:external_id]
      assert_equal "Video One", first[:title]
      assert_equal "https://www.bitchute.com/video/UA8c4dHy7zI/", first[:url]
      assert_equal Time.parse("2026-09-07T08:25:20Z"), first[:published_at]
      assert_equal 609, first[:views]
      assert_equal "desc one", first[:content_text]
      assert_equal "C1", first[:creator_identity][:external_id]

      assert_includes captured.first, "api.bitchute.com/api/beta/channel/videos"
      assert_equal "C1", captured.last[:channel_id]
    end
  end

  test "channel_feed paginates until a short page, respecting limit" do
    page = ->(n, prefix) { Array.new(n) { |i| { "video_id" => "#{prefix}#{i}", "video_name" => "V", "video_url" => "/video/x/", "date_published" => "2026-09-07T08:25:20Z", "duration" => "1:00", "thumbnail_url" => nil, "view_count" => 1, "description" => "d" } } }
    full = page.call(50, "a")
    short = page.call(20, "b")
    calls = 0
    PoliteCrawl.stub(:post, lambda { |_url, **_opts|
      body = calls.zero? ? full : short
      calls += 1
      OpenStruct.new(status: 200, body: { "videos" => body }.to_json)
    }) do
      items = Stray::Bridges::Bitchute.new.channel_feed("https://www.bitchute.com/channel/C1", limit: 100)

      assert_equal 70, items.size
      assert_equal 2, calls
    end
  end

  test "channel_feed honors a small limit without extra requests" do
    full = Array.new(50) { |i| { "video_id" => "a#{i}", "video_name" => "V", "video_url" => "/video/x/", "date_published" => "2026-09-07T08:25:20Z", "duration" => "1:00", "thumbnail_url" => nil, "view_count" => 1, "description" => "d" } }
    calls = 0
    PoliteCrawl.stub(:post, lambda { |_url, **_opts|
      calls += 1
      OpenStruct.new(status: 200, body: { "videos" => full }.to_json)
    }) do
      items = Stray::Bridges::Bitchute.new.channel_feed("https://www.bitchute.com/channel/C1", limit: 20)

      assert_equal 20, items.size
      assert_equal 1, calls
    end
  end

  test "channel_feed returns [] when the URL has no channel id" do
    PoliteCrawl.stub(:post, ->(*_args) { raise "should not fetch" }) do
      assert_equal [], Stray::Bridges::Bitchute.new.channel_feed("https://www.bitchute.com/video/abc")
    end
  end

  test "channel_feed raises ExtractionError on a non-200 response" do
    PoliteCrawl.stub(:post, ->(*_args) { OpenStruct.new(status: 404, body: "nope") }) do
      assert_raises(Stray::ExtractionError) do
        Stray::Bridges::Bitchute.new.channel_feed("https://www.bitchute.com/channel/C1")
      end
    end
  end

  test "video_page posts to the single-video API and normalizes creator + hashtags" do
    captured = nil
    PoliteCrawl.stub(:post, lambda { |url, **opts| captured = [ url, opts[:json] ]; OpenStruct.new(status: 200, body: SAMPLE_VIDEO_DETAIL.to_json) }) do
      page = Stray::Bridges::Bitchute.new.video_page("https://www.bitchute.com/video/UA8c4dHy7zI")

      assert_equal "UA8c4dHy7zI", page[:external_id]
      assert_equal "Video One", page[:title]
      assert_equal "https://www.bitchute.com/video/UA8c4dHy7zI/", page[:url]
      assert_equal Time.parse("2026-09-07T08:25:20Z"), page[:published_at]
      assert_equal 910, page[:duration]
      assert_equal 609, page[:views]
      assert_equal %w[politics news], page[:tags]
      assert_equal "Stew Peters", page[:creator_identity][:name]
      assert_equal "C1", page[:creator_identity][:external_id]
      assert_equal "https://www.bitchute.com/channel/C1", page[:creator_identity][:url]
      assert_equal "https://static-3.bitchute.com/live/channel_images/C1/banner.jpg", page[:creator_identity][:thumbnail_url]

      assert_includes captured.first, "api.bitchute.com/api/beta/video"
      assert_equal "UA8c4dHy7zI", captured.last[:video_id]
    end
  end

  test "video_page returns nil when the URL has no video id" do
    PoliteCrawl.stub(:post, ->(*_args) { raise "should not fetch" }) do
      assert_nil Stray::Bridges::Bitchute.new.video_page("https://www.bitchute.com/channel/C1")
    end
  end

  test "video_page raises ExtractionError on a non-200 response" do
    PoliteCrawl.stub(:post, ->(*_args) { OpenStruct.new(status: 404, body: "nope") }) do
      assert_raises(Stray::ExtractionError) do
        Stray::Bridges::Bitchute.new.video_page("https://www.bitchute.com/video/UA8c4dHy7zI")
      end
    end
  end
end
