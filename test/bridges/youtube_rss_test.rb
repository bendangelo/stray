require "test_helper"
require "ostruct"

class Bridges::YoutubeRssTest < ActiveSupport::TestCase
  test "matches? returns true for YouTube RSS feed URLs" do
    assert Bridges::YoutubeRss.matches?("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
    assert Bridges::YoutubeRss.matches?("https://youtube.com/feeds/videos.xml?channel_id=UC123")
  end

  test "matches? returns false for non-RSS YouTube URLs" do
    assert_not Bridges::YoutubeRss.matches?("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    assert_not Bridges::YoutubeRss.matches?("https://www.youtube.com/@channel")
    assert_not Bridges::YoutubeRss.matches?("https://www.youtube.com/channel/UC123")
  end

  test "matches? returns false for non-YouTube URLs" do
    assert_not Bridges::YoutubeRss.matches?("https://example.com/feed.xml")
    assert_not Bridges::YoutubeRss.matches?("https://bitchute.com/channel/abc")
  end

  test "handles_kind? returns true for youtube_channel" do
    assert Bridges::YoutubeRss.handles_kind?("youtube_channel")
  end

  test "handles_kind? returns false for other kinds" do
    assert_not Bridges::YoutubeRss.handles_kind?("rss_feed")
    assert_not Bridges::YoutubeRss.handles_kind?("video_channel")
  end

  test "extract returns array of Stray::ExtractedContent from RSS feed" do
    VCR.use_cassette("extractors/youtube_rss_feed") do
      extractor = Bridges::YoutubeRss.new
      results = extractor.extract("https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw")

      assert_equal 2, results.size
      first = results.first
      assert_equal "dQw4w9WgXcQ", first.external_id
      assert_equal "https://www.youtube.com/watch?v=dQw4w9WgXcQ", first.url
      assert_equal "Rick Astley - Never Gonna Give You Up (Official Music Video)", first.title
      assert_equal "The official video for Never Gonna Give You Up by Rick Astley.", first.content_text
      assert_equal "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg", first.thumbnail_url
      assert_equal Time.parse("2009-10-25T00:00:00+00:00"), first.published_at
      assert_nil first.duration
    end
  end

  test "http_client sends a browser User-Agent, Accept-Language, and CONSENT cookie" do
    client = Bridges::YoutubeRss.new.send(:http_client)

    assert_equal Bridges::YoutubeRss::BROWSER_UA, client.headers["User-Agent"]
    assert_equal "en", client.headers["Accept-Language"]
    assert_equal "CONSENT=YES+cb", client.headers["Cookie"]
  end

  test "extract raises Stray::ExtractionError with status on non-200 response" do
    response = Struct.new(:status, :body).new(404, "<html>not found</html>")
    client = Minitest::Mock.new
    client.expect(:get, response, [ String ])

    extractor = Bridges::YoutubeRss.new
    extractor.stub(:http_client, client) do
      error = assert_raises(Stray::ExtractionError) do
        extractor.extract("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
      end
      assert_equal "youtube rss fetch failed: 404", error.message
    end
  end

  test "extract includes creator_identity from feed author" do
    VCR.use_cassette("extractors/youtube_rss_feed") do
      extractor = Bridges::YoutubeRss.new
      results = extractor.extract("https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw")

      creator = results.first.creator_identity
      assert_equal "Rick Astley", creator.name
      assert_equal "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw", creator.url
      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", creator.external_id
    end
  end

  test "extract_backfill maps flat-playlist JSON to ExtractedContent with video-id external_id" do
    listing1 = '{"id":"dQw4w9WgXcQ","title":"Video 1","url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ","upload_date":"20240101","channel":"Rick Astley","channel_id":"UCuAXFkgsw1L7xaCfnd5JJOw","channel_url":"https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw","thumbnails":[{"url":"https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg"}]}'
    listing2 = '{"id":"abc123def45","title":"Video 2","url":"https://www.youtube.com/watch?v=abc123def45","upload_date":"20240102","channel":"Rick Astley","channel_id":"UCuAXFkgsw1L7xaCfnd5JJOw","channel_url":"https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw","thumbnails":[{"url":"https://i.ytimg.com/vi/abc123def45/mqdefault.jpg"}]}'
    multi_json = "#{listing1}\n#{listing2}\n"

    runner = Stray::YtDlp::Runner.new
    runner.define_singleton_method(:execute) { |*_args| [ multi_json, "", OpenStruct.new(success?: true) ] }
    Stray::YtDlp::Runner.stub(:new, runner) do
      extractor = Bridges::YoutubeRss.new
      results = extractor.extract_backfill("https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw", limit: 50)

      assert_equal 2, results.size
      first = results.first
      assert_equal "dQw4w9WgXcQ", first.external_id
      assert_equal "https://www.youtube.com/watch?v=dQw4w9WgXcQ", first.url
      assert_equal "Video 1", first.title
      assert_equal Time.strptime("20240101", "%Y%m%d"), first.published_at
      assert_equal "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg", first.thumbnail_url
      assert_equal "Rick Astley", first.creator_identity.name
    end
  end

  test "extract_backfill passes the channel videos URL and limit to the runner" do
    captured = nil
    runner = Stray::YtDlp::Runner.new
    runner.define_singleton_method(:execute) { |*args| captured = args; [ "", "", OpenStruct.new(success?: true) ] }
    Stray::YtDlp::Runner.stub(:new, runner) do
      Bridges::YoutubeRss.new.extract_backfill("https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw", limit: 50)
    end
    assert_includes captured, "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw/videos"
    assert_includes captured, "--playlist-end"
    assert_includes captured, "50"
  end
end
