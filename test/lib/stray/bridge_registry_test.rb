require "test_helper"

class Stray::BridgeRegistryTest < ActiveSupport::TestCase
  class FakeYoutubeRss < Stray::Bridge
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

    def extract_feed(url) = extract(url)
  end

  class FakeYtDlp < Stray::Bridge
    def self.matches?(url) = true
    def self.handles_kind?(kind) = kind == "video_channel"
    def extract(url) = FakeYoutubeRss.new.extract(url)
    def extract_feed(url) = extract(url)
  end

  def setup
    @original = Stray::BridgeRegistry.instance_variable_get(:@bridges)
    Stray::BridgeRegistry.reset!
    Stray::BridgeRegistry.register(FakeYoutubeRss)
    Stray::BridgeRegistry.register(FakeYtDlp)
  end

  def teardown
    Stray::BridgeRegistry.reset!
    @original&.each { |b| Stray::BridgeRegistry.register(b) }
  end

  test "find_for returns first matching bridge" do
    bridge = Stray::BridgeRegistry.find_for("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
    assert_equal FakeYoutubeRss, bridge.class
  end

  test "find_for falls back to universal bridge" do
    bridge = Stray::BridgeRegistry.find_for("https://bitchute.com/video/abc123")
    assert_equal FakeYtDlp, bridge.class
  end

  test "find_for returns nil when nothing matches" do
    Stray::BridgeRegistry.reset!
    assert_nil Stray::BridgeRegistry.find_for("https://example.com")
  end

  test "registration order determines priority" do
    Stray::BridgeRegistry.reset!
    Stray::BridgeRegistry.register(FakeYtDlp)
    Stray::BridgeRegistry.register(FakeYoutubeRss)
    bridge = Stray::BridgeRegistry.find_for("https://www.youtube.com/feeds/videos.xml?channel_id=UC123")
    assert_equal FakeYtDlp, bridge.class
  end

  test "find_for_source returns bridge matching source kind" do
    source = Source.new(kind: :youtube_channel, url: "https://example.com")
    assert_equal FakeYoutubeRss, Stray::BridgeRegistry.find_for_source(source).class
  end

  test "find_for_source returns nil when no bridge handles kind" do
    Stray::BridgeRegistry.reset!
    source = Source.new(kind: :generic_page, url: "https://example.com")
    assert_nil Stray::BridgeRegistry.find_for_source(source)
  end

  test "find_for_source falls back to YtDlp for video_channel with no dedicated bridge" do
    Stray::BridgeRegistry.reset!
    Stray::BridgeRegistry.register(FakeYoutubeRss)
    source = Source.new(kind: :video_channel, url: "https://somesite.com/channel/foo")
    assert_nil Stray::BridgeRegistry.find_for_source(source)
  end

  test "find_for_source returns YtDlp for video_channel when YtDlp is registered" do
    source = Source.new(kind: :video_channel, url: "https://somesite.com/channel/foo")
    assert_equal FakeYtDlp, Stray::BridgeRegistry.find_for_source(source).class
  end
end
