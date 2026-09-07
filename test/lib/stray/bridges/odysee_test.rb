require "test_helper"
require "ostruct"

class Stray::Bridges::OdyseeTest < ActiveSupport::TestCase
  FIXTURE = File.expand_path("../../../fixtures/files/odysee_rss.xml", __dir__)

  def stub_feed(body)
    resp = OpenStruct.new(status: 200, body: body)
    extractor = Stray::Bridges::Odysee.new
    extractor.define_singleton_method(:fetch) { |_url| resp }
    yield extractor
  end

  test "matches? returns true for odysee URLs" do
    assert Stray::Bridges::Odysee.matches?("https://odysee.com/@samtime:1")
  end

  test "matches? returns false for non-odysee URLs" do
    assert_not Stray::Bridges::Odysee.matches?("https://example.com")
  end

  test "channel_handle parses @handle:id" do
    assert_equal "samtime:1", Stray::Bridges::Odysee.channel_handle("https://odysee.com/@samtime:1")
  end

  test "rss_url builds the feed URL" do
    assert_equal "https://odysee.com/$/rss/@samtime:1",
                 Stray::Bridges::Odysee.rss_url("https://odysee.com/@samtime:1")
  end

  test "channel_feed parses RSS entries" do
    stub_feed(File.read(FIXTURE)) do |extractor|
      items = extractor.channel_feed("https://odysee.com/@samtime:1")
      assert items.any?

      first = items.first
      assert_equal "https://odysee.com/apple-reacts-to-the-new-framework-laptop:f0bfe667ed0eb53f55aa9ba6fea16d827ec9b43d", first[:url]
      assert first[:title].present?
      assert first[:published_at].is_a?(Time)
      assert first[:external_id].present?
      assert_equal "SAMTIME on Odysee", first[:creator_identity][:name]
      assert_equal "https://thumbnails.lbry.com/XF2WniCfmEE", first[:thumbnail_url]
      assert first[:content_html].present?
      assert_equal "https://thumbnails.lbry.com/UCd6vEDS3SOhWbXZrxbrf_bw", first[:creator_identity][:thumbnail_url]
    end
  end

  test "channel_feed raises for non-channel URL" do
    assert_raises(Stray::ExtractionError) do
      Stray::Bridges::Odysee.new.channel_feed("https://odysee.com/some-video")
    end
  end

  test "feed_from_rss parses RSS body without fetching" do
    body = File.read(Rails.root.join("test/fixtures/files/odysee_rss.xml"))
    items = Stray::Bridges::Odysee.new.feed_from_rss(body, "https://odysee.com/@test:1")
    assert items.any?
  end

  test "video_page extracts metadata from yt-dlp JSON" do
    video_json = {
      "id" => "some-video:49",
      "title" => "Test Odysee Video",
      "description" => "A test video",
      "duration" => 600,
      "upload_date" => "20240115",
      "thumbnail" => "https://example.com/thumb.jpg",
      "url" => "https://odysee.com/@SkyLight33:7/some-video:49",
      "channel" => "SkyLight33",
      "channel_id" => "SkyLight33:7"
    }

    runner = Stray::YtDlp::Runner.new
    runner.define_singleton_method(:single_video) { |_url| video_json }

    Stray::YtDlp::Runner.stub(:new, runner) do
      result = Stray::Bridges::Odysee.new.video_page("https://odysee.com/@SkyLight33:7/some-video:49")

      assert_equal "Test Odysee Video", result[:title]
      assert_equal "some-video:49", result[:external_id]
      assert_equal "https://odysee.com/@SkyLight33:7/some-video:49", result[:url]
      assert_equal "https://example.com/thumb.jpg", result[:thumbnail_url]
      assert_equal 600, result[:duration]
      assert_equal Time.strptime("20240115", "%Y%m%d"), result[:published_at]
      assert_equal "A test video", result[:content_text]

      creator = result[:creator_identity]
      assert_equal "SkyLight33", creator[:name]
      assert_equal "SkyLight33:7", creator[:external_id]
      assert_equal "https://odysee.com/@SkyLight33:7", creator[:url]
    end
  end
end
