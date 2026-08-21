require "test_helper"

class ImagesHelperTest < ActionView::TestCase
  include ApplicationHelper

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
    assert_includes html, "error->image-fallback#onError"
    assert_includes html, "image_fallback_target"
    assert_includes html, "/fallback.jpg"
    assert_includes html, 'loading="lazy"'
  end

  test "fallback_image_tag uses missing_thumb default when no fallback given" do
    html = fallback_image_tag("https://example.com/a.jpg", alt: "A")
    assert_includes html, "missing-video.jpg"
  end
end
