require "test_helper"

class ExtractorRegistryTest < ActiveSupport::TestCase
  class FakeYoutubeRss < Extractor
    def self.matches?(url)
      URI.parse(url).path == "/feeds/videos.xml"
    rescue URI::InvalidURIError
      false
    end

    def self.handles_kind?(kind)
      kind == "youtube_channel"
    end

    def extract(url)
      ExtractedContent.new(url: "https://example.com/video", title: "test", content_text: nil, content_html: nil,
        thumbnail_url: nil, published_at: nil, external_id: "x", duration: nil, creator_identity: nil, tags: [])
    end

    def extract_feed(url)
      extract(url)
    end
  end

  class FakeYtDlp < Extractor
    def self.matches?(url)
      true
    end

    def self.handles_kind?(kind)
      kind == "video_channel"
    end

    def extract(url)
      ExtractedContent.new(url: "https://example.com/video", title: "test", content_text: nil, content_html: nil,
        thumbnail_url: nil, published_at: nil, external_id: "x", duration: nil, creator_identity: nil, tags: [])
    end

    def extract_feed(url)
      extract(url)
    end
  end

  def setup
    @original_extractors = ExtractorRegistry.instance_variable_get(:@extractors)
    ExtractorRegistry.reset!
    ExtractorRegistry.register(FakeYoutubeRss)
    ExtractorRegistry.register(FakeYtDlp)
  end

  def teardown
    ExtractorRegistry.reset!
    @original_extractors&.each { |e| ExtractorRegistry.register(e) }
  end

  test "find_for returns first matching extractor" do
    extractor = ExtractorRegistry.find_for("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
    assert_equal FakeYoutubeRss, extractor.class
  end

  test "find_for falls back to universal extractor" do
    extractor = ExtractorRegistry.find_for("https://bitchute.com/video/abc123")
    assert_equal FakeYtDlp, extractor.class
  end

  test "find_for returns nil when nothing matches" do
    ExtractorRegistry.reset!
    assert_nil ExtractorRegistry.find_for("https://example.com")
  end

  test "registration order determines priority" do
    ExtractorRegistry.reset!
    ExtractorRegistry.register(FakeYtDlp)
    ExtractorRegistry.register(FakeYoutubeRss)
    extractor = ExtractorRegistry.find_for("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
    assert_equal FakeYtDlp, extractor.class
  end

  test "find_for_source returns extractor matching source kind" do
    source = Source.new(kind: :youtube_channel, url: "https://example.com")
    extractor = ExtractorRegistry.find_for_source(source)
    assert_equal FakeYoutubeRss, extractor.class
  end

  test "find_for_source returns nil when no extractor handles kind" do
    ExtractorRegistry.reset!
    source = Source.new(kind: :generic_page, url: "https://example.com")
    assert_nil ExtractorRegistry.find_for_source(source)
  end
end
