require "test_helper"
require "ostruct"
require "minitest/mock"

class Stray::Extractors::YtDlpTest < ActiveSupport::TestCase
  FIXTURE_PATH = File.expand_path("../../../fixtures/files/yt_dlp_video.json", __dir__)

  def setup
    @json = File.read(FIXTURE_PATH)
    @data = JSON.parse(@json)
  end

  def status_success
    OpenStruct.new(success?: true)
  end

  test "matches? returns true for any URL (universal fallback)" do
    assert Stray::Extractors::YtDlp.matches?("https://bitchute.com/video/abc123")
    assert Stray::Extractors::YtDlp.matches?("https://rumble.com/vabc123.html")
    assert Stray::Extractors::YtDlp.matches?("https://vimeo.com/12345")
  end

  test "matches? returns false for YouTube RSS feed URLs (handled by YoutubeRss)" do
    assert_not Stray::Extractors::YtDlp.matches?("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
  end

  test "handles_kind? returns true for video_channel" do
    assert Stray::Extractors::YtDlp.handles_kind?("video_channel")
  end

  test "handles_kind? returns false for other kinds" do
    assert_not Stray::Extractors::YtDlp.handles_kind?("youtube_channel")
    assert_not Stray::Extractors::YtDlp.handles_kind?("rss_feed")
  end

  test "extract returns ExtractedContent with video metadata" do
    Open3.stub(:capture3, [ @json, "", status_success ]) do
      extractor = Stray::Extractors::YtDlp.new
      result = extractor.extract("https://bitchute.com/video/abc123")

      assert_equal "dQw4w9WgXcQ", result.external_id
      assert_equal "https://www.bitchute.com/video/dQw4w9WgXcQ", result.url
      assert_equal "Rick Astley - Never Gonna Give You Up (Official Music Video)", result.title
      assert_equal "The official video for Never Gonna Give You Up by Rick Astley.", result.content_text
      assert_equal "https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg", result.thumbnail_url
      assert_equal 213, result.duration
      assert_equal Time.strptime("20091025", "%Y%m%d"), result.published_at
    end
  end

  test "extract includes creator_identity" do
    Open3.stub(:capture3, [ @json, "", status_success ]) do
      extractor = Stray::Extractors::YtDlp.new
      result = extractor.extract("https://bitchute.com/video/abc123")

      creator = result.creator_identity
      assert_equal "Rick Astley", creator.name
      assert_equal "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw", creator.url
      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", creator.external_id
    end
  end

  test "extracts tags from yt-dlp JSON" do
    data = @data.merge(
      "categories" => [ "Education", "Technology" ],
      "tags" => [ "ruby", "rails", "web" ]
    )
    Open3.stub(:capture3, [ data.to_json, "", status_success ]) do
      extractor = Stray::Extractors::YtDlp.new
      content = extractor.extract("https://bitchute.com/video/abc123")

      assert_includes content.tags, "education"
      assert_includes content.tags, "technology"
      assert_includes content.tags, "ruby"
      assert content.tags.length <= 5
    end
  end

  test "extract raises ExtractionFailed when yt-dlp fails" do
    Open3.stub(:capture3, [ "", "", OpenStruct.new(success?: false) ]) do
      extractor = Stray::Extractors::YtDlp.new
      assert_raises(Stray::YtDlp::ExtractionFailed) do
        extractor.extract("https://example.com/video")
      end
    end
  end

  test "extract canonicalizes channel-prefixed bitchute URLs" do
    data = @data.merge("id" => "abc123", "url" => "https://www.bitchute.com/channel/Foo//video/abc123")
    Open3.stub(:capture3, [ data.to_json, "", status_success ]) do
      extractor = Stray::Extractors::YtDlp.new
      result = extractor.extract("https://www.bitchute.com/channel/Foo//video/abc123")

      assert_equal "https://www.bitchute.com/video/abc123", result.url
    end
  end

  test "extract leaves non-bitchute URLs unchanged" do
    data = @data.merge("url" => "https://vimeo.com/12345")
    Open3.stub(:capture3, [ data.to_json, "", status_success ]) do
      extractor = Stray::Extractors::YtDlp.new
      result = extractor.extract("https://vimeo.com/12345")

      assert_equal "https://vimeo.com/12345", result.url
    end
  end

  test "extract_channel canonicalizes bitchute listing URLs" do
    listing = '{"id":"vid1","title":"Video 1","url":"https://www.bitchute.com/channel/Foo//video/vid1","channel":"Test","channel_id":"C1","channel_url":"https://www.bitchute.com/channel/Foo"}'
    Open3.stub(:capture3, [ "#{listing}\n", "", status_success ]) do
      extractor = Stray::Extractors::YtDlp.new
      results = extractor.extract_channel("https://www.bitchute.com/channel/Foo")

      assert_equal "https://www.bitchute.com/video/vid1", results[0].url
    end
  end

  test "extract_channel returns array of lightweight ExtractedContent" do
    listing1 = '{"id":"vid1","title":"Video 1","url":"https://example.com/v1","channel":"Test","channel_id":"C1","channel_url":"https://example.com/c1"}'
    listing2 = '{"id":"vid2","title":"Video 2","url":"https://example.com/v2","channel":"Test","channel_id":"C1","channel_url":"https://example.com/c1"}'
    multi_json = "#{listing1}\n#{listing2}\n"

    Open3.stub(:capture3, [ multi_json, "", status_success ]) do
      extractor = Stray::Extractors::YtDlp.new
      results = extractor.extract_channel("https://bitchute.com/channel/abc")

      assert_equal 2, results.size
      assert_equal "vid1", results[0].external_id
      assert_equal "https://example.com/v1", results[0].url
      assert_equal "Video 1", results[0].title
    end
  end
end
