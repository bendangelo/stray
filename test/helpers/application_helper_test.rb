require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "pretty_duration handles seconds under a minute" do
    assert_equal "0:45", pretty_duration(45)
  end

  test "pretty_duration handles minutes" do
    assert_equal "3:05", pretty_duration(185)
  end

  test "pretty_duration handles hours" do
    assert_equal "1:30:00", pretty_duration(5400)
  end

  test "pretty_duration returns empty string for nil" do
    assert_equal "", pretty_duration(nil)
  end

  test "pretty_duration returns empty string for zero" do
    assert_equal "", pretty_duration(0)
  end

  test "embed_url constructs YouTube embed URL" do
    source = sources(:youtube)
    item = items(:video_one)
    url = embed_url(item)
    assert_equal "https://www.youtube.com/embed/#{item.external_id}", url
  end

  test "embed_url returns nil for unknown source kind" do
    source = sources(:bitchute)
    item = items(:video_saved)
    url = embed_url(item)
    assert_equal "https://www.bitchute.com/embed/#{item.external_id}", url
  end

  test "missing_thumb returns a data URI" do
    assert_match(/^data:image\/svg\+xml/, missing_thumb)
  end
end
