require "test_helper"

class Stray::ExtractorRegistryTest < ActiveSupport::TestCase
  class FakeYoutubeRss < Stray::Extractor
    def self.matches?(url)
      URI.parse(url).path == "/feeds/videos.xml"
    rescue URI::InvalidURIError
      false
    end

    def self.handles_kind?(kind)
      kind == "youtube_channel"
    end

    def extract(url)
      Stray::ExtractedContent.new(url: "https://example.com/video", title: "test", content_text: nil, content_html: nil,
        thumbnail_url: nil, published_at: nil, external_id: "x", duration: nil, creator_identity: nil, tags: [])
    end

    def extract_feed(url)
      extract(url)
    end
  end

  class FakeYtDlp < Stray::Extractor
    def self.matches?(url)
      true
    end

    def self.handles_kind?(kind)
      kind == "video_channel"
    end

    def extract(url)
      Stray::ExtractedContent.new(url: "https://example.com/video", title: "test", content_text: nil, content_html: nil,
        thumbnail_url: nil, published_at: nil, external_id: "x", duration: nil, creator_identity: nil, tags: [])
    end

    def extract_feed(url)
      extract(url)
    end
  end

  def setup
    @original_extractors = Stray::ExtractorRegistry.instance_variable_get(:@extractors)
    Stray::ExtractorRegistry.reset!
    Stray::ExtractorRegistry.register(FakeYoutubeRss)
    Stray::ExtractorRegistry.register(FakeYtDlp)
  end

  def teardown
    Stray::ExtractorRegistry.reset!
    @original_extractors&.each { |e| Stray::ExtractorRegistry.register(e) }
  end

  test "find_for returns first matching extractor" do
    extractor = Stray::ExtractorRegistry.find_for("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
    assert_equal FakeYoutubeRss, extractor.class
  end

  test "find_for falls back to universal extractor" do
    extractor = Stray::ExtractorRegistry.find_for("https://bitchute.com/video/abc123")
    assert_equal FakeYtDlp, extractor.class
  end

  test "find_for returns nil when nothing matches" do
    Stray::ExtractorRegistry.reset!
    assert_nil Stray::ExtractorRegistry.find_for("https://example.com")
  end

  test "registration order determines priority" do
    Stray::ExtractorRegistry.reset!
    Stray::ExtractorRegistry.register(FakeYtDlp)
    Stray::ExtractorRegistry.register(FakeYoutubeRss)
    extractor = Stray::ExtractorRegistry.find_for("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
    assert_equal FakeYtDlp, extractor.class
  end

  test "find_for_source returns extractor matching source kind" do
    source = Source.new(kind: :youtube_channel, url: "https://example.com")
    extractor = Stray::ExtractorRegistry.find_for_source(source)
    assert_equal FakeYoutubeRss, extractor.class
  end

  test "find_for_source returns nil when no extractor handles kind" do
    Stray::ExtractorRegistry.reset!
    source = Source.new(kind: :generic_page, url: "https://example.com")
    assert_nil Stray::ExtractorRegistry.find_for_source(source)
  end
end
