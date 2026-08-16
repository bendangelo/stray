require "test_helper"

class Stray::ExtractorRegistryTest < ActiveSupport::TestCase
  class FakeYoutubeRss < Stray::Extractor
    def self.matches?(url)
      URI.parse(url).path == "/feeds/videos.xml"
    rescue URI::InvalidURIError
      false
    end

    def extract(url)
      Stray::ExtractedContent.new(title: "test", content_text: nil, content_html: nil,
        thumbnail_url: nil, published_at: nil, external_id: "x", duration: nil, creator_identity: nil, tags: [])
    end
  end

  class FakeYtDlp < Stray::Extractor
    def self.matches?(url)
      true
    end

    def extract(url)
      Stray::ExtractedContent.new(title: "test", content_text: nil, content_html: nil,
        thumbnail_url: nil, published_at: nil, external_id: "x", duration: nil, creator_identity: nil, tags: [])
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
end
