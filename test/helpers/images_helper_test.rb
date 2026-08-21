require "test_helper"

class ImagesHelperTest < ActionView::TestCase
  include ApplicationHelper
  include SourcesHelper

  test "fallback_image_tag with nil src renders fallback directly without controller" do
    html = fallback_image_tag(nil, fallback: "/fallback.jpg", alt: "x", class: "w-10")
    assert_includes html, "/fallback.jpg"
    assert_includes html, "w-10"
    refute_includes html, "data-controller"
    refute_includes html, "image-fallback"
  end

  test "fallback_image_tag with empty src renders fallback directly without controller" do
    html = fallback_image_tag("", fallback: "/fallback.jpg", alt: "x")
    assert_includes html, "/fallback.jpg"
    refute_includes html, "data-controller"
  end

  test "fallback_image_tag with src renders wrapper with controller and img" do
    html = fallback_image_tag("https://example.com/a.jpg", fallback: "/fallback.jpg", alt: "A", class: "thumb")
    assert_includes html, "data-controller"
    assert_includes html, "image-fallback"
    assert_includes html, "https://example.com/a.jpg"
    assert_includes html, "thumb"
    assert_includes html, "error-&gt;image-fallback#onError"
    assert_includes html, "data-image-fallback-target"
    assert_includes html, "/fallback.jpg"
    assert_includes html, 'loading="lazy"'
  end

  test "fallback_image_tag uses missing_thumb default when no fallback given" do
    html = fallback_image_tag("https://example.com/a.jpg", alt: "A")
    assert_includes html, "missing-video.jpg"
  end

  test "source_icon_tag with icon_url renders wrapper, img, and hidden letter div" do
    source = Source.new(url: "https://example.com", name: "Example", icon_url: "https://example.com/icon.png")
    html = source_icon_tag(source, size: "w-8 h-8")
    assert_includes html, "data-controller"
    assert_includes html, "image-fallback"
    assert_includes html, "https://example.com/icon.png"
    assert_includes html, "data-image-fallback-target"
    assert_includes html, "error-&gt;image-fallback#onError"
    assert_includes html, ">E<"  # the letter
    assert_includes html, "hidden"  # letter div starts hidden
  end

  test "source_icon_tag with nil icon_url but valid source url uses DuckDuckGo favicon" do
    source = Source.new(url: "https://bitchute.com/channel/feedbc", name: "BC", icon_url: nil)
    html = source_icon_tag(source, size: "w-8 h-8")
    assert_includes html, "https://icons.duckduckgo.com/ip3/bitchute.com.ico"
    assert_includes html, "data-controller"
    assert_includes html, "image-fallback"
    assert_includes html, "hidden"  # letter fallback div
    assert_includes html, ">B<"  # letter B
  end

  test "source_icon_tag with invalid url renders letter div only, no img, no controller" do
    source = Source.new(url: "not-a-url", name: "Foo", icon_url: nil)
    html = source_icon_tag(source, size: "w-8 h-8")
    assert_includes html, ">F<"
    refute_includes html, "<img"
    refute_includes html, "data-controller"
    refute_includes html, "image-fallback"
  end

  test "source_icon_tag applies class param to the wrapper" do
    source = Source.new(url: "https://example.com", name: "Example", icon_url: "https://example.com/icon.png")
    html = source_icon_tag(source, size: "w-5 h-5", class: "absolute left-2 bottom-2")
    assert_includes html, "absolute left-2 bottom-2"
  end

  test "source_icon_tag handles empty source name gracefully" do
    source = Source.new(url: "not-a-url", name: "", icon_url: nil)
    html = source_icon_tag(source, size: "w-8 h-8")
    refute_includes html, "<img"
    refute_includes html, "data-controller"
  end
end
