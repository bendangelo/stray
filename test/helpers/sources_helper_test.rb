require "test_helper"

class SourcesHelperTest < ActionView::TestCase
  test "source_icon_url returns icon_url when present" do
    source = Source.new(url: "https://example.com", icon_url: "https://example.com/icon.png")
    assert_equal "https://example.com/icon.png", source_icon_url(source)
  end

  test "source_icon_url falls back to DuckDuckGo for youtube URLs" do
    source = Source.new(url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCfeed", icon_url: nil)
    assert_equal "https://icons.duckduckgo.com/ip3/www.youtube.com.ico", source_icon_url(source)
  end

  test "source_icon_url falls back to DuckDuckGo for generic URLs" do
    source = Source.new(url: "https://bitchute.com/channel/feedbc", icon_url: nil)
    assert_equal "https://icons.duckduckgo.com/ip3/bitchute.com.ico", source_icon_url(source)
  end

  test "source_icon_url returns nil for invalid URLs" do
    source = Source.new(url: "not-a-url", icon_url: nil)
    assert_nil source_icon_url(source)
  end

  test "source_icon renders image with icon_url when present" do
    source = Source.new(url: "https://example.com", name: "Example", icon_url: "https://example.com/icon.png")
    html = source_icon(source)
    assert_includes html, "https://example.com/icon.png"
    assert_match(/<img/, html)
  end

  test "source_icon falls back to favicon image when icon_url is nil" do
    source = Source.new(url: "https://bitchute.com/channel/feedbc", name: "BC Channel", icon_url: nil)
    html = source_icon(source)
    assert_includes html, "https://icons.duckduckgo.com/ip3/bitchute.com.ico"
    assert_match(/<img/, html)
  end

  test "source_icon renders letter avatar for invalid URLs" do
    source = Source.new(url: "not-a-url", name: "B", icon_url: nil)
    html = source_icon(source)
    assert_includes html, "B"
    refute_match(/<img/, html)
  end
end
