require "test_helper"
require "ostruct"

class Stray::Bridges::PeertubeTest < ActiveSupport::TestCase
  FIXTURE = File.expand_path("../../../fixtures/files/peertube_videos.json", __dir__)
  VIDEO_FIXTURE = File.expand_path("../../../fixtures/files/peertube_video.json", __dir__)

  def stub_json(body)
    resp = OpenStruct.new(status: 200, body: body)
    extractor = Stray::Bridges::Peertube.new
    extractor.define_singleton_method(:fetch) { |_url| resp }
    yield extractor
  end

  test "matches? returns true for video-channels URLs" do
    assert Stray::Bridges::Peertube.matches?("https://tilvids.com/video-channels/fedi")
    assert Stray::Bridges::Peertube.matches?("https://tilvids.com/c/fedi")
  end

  test "matches? returns false for generic URLs" do
    assert_not Stray::Bridges::Peertube.matches?("https://tilvids.com/videos/trending")
  end

  test "channel_handle parses video-channels and c paths" do
    assert_equal "fedi", Stray::Bridges::Peertube.channel_handle("https://tilvids.com/video-channels/fedi")
    assert_equal "fedi", Stray::Bridges::Peertube.channel_handle("https://tilvids.com/c/fedi")
  end

  test "channel_feed parses API videos" do
    stub_json(File.read(FIXTURE)) do |extractor|
      items = extractor.channel_feed("https://video.tkz.es/video-channels/fedi")
      assert_equal 1, items.size

      first = items.first
      assert_equal "8681e152-265f-42dc-80cd-7333fd4feb6d", first[:external_id]
      assert_equal 145, first[:duration]
      assert first[:published_at].is_a?(Time)
      assert_equal 43, first[:views]
      assert_equal "Fediverso", first[:creator_identity][:name]
      assert_equal "fedi", first[:creator_identity][:external_id]
    end
  end

  test "channel_feed raises for non-channel URL" do
    assert_raises(Stray::ExtractionError) do
      Stray::Bridges::Peertube.new.channel_feed("https://video.tkz.es/videos/trending")
    end
  end

  test "channel_feed listing API omits tags" do
    stub_json(File.read(FIXTURE)) do |extractor|
      items = extractor.channel_feed("https://video.tkz.es/video-channels/fedi")
      assert_equal 1, items.size
      assert_equal [], items.first[:tags]
    end
  end

  test "fetch_tags returns tags from the single-video endpoint" do
    stub_json(File.read(VIDEO_FIXTURE)) do |extractor|
      tags = extractor.fetch_tags("tube.xy-space.de", "6aa95cf7-08af-4b22-86af-b7563e2ff4bd")
      assert_equal [ "Documentary", "information", "Society" ], tags
    end
  end
end
