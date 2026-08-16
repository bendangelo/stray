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

  test "embed_url constructs Bitchute embed URL" do
    source = sources(:bitchute)
    item = items(:video_saved)
    url = embed_url(item)
    assert_equal "https://www.bitchute.com/embed/#{item.external_id}", url
  end

  test "embed_url returns nil for unknown source kind" do
    source = Source.create!(user: users(:one), kind: :rss_feed, url: "https://example.com/feed", external_id: "feed1")
    item = Item.create!(source: source, user: users(:one), external_id: "e1", title: "Post", url: "https://example.com/post")

    assert_nil embed_url(item)
  end

  test "missing_thumb returns a data URI" do
    assert_match(/^data:image\/svg\+xml/, missing_thumb)
  end

  test "video? is true for youtube_channel" do
    source = Source.new(kind: :youtube_channel)
    item = Item.new(source: source)
    assert video?(item)
  end

  test "video? is true for video_channel" do
    source = Source.new(kind: :video_channel)
    item = Item.new(source: source)
    assert video?(item)
  end

  test "video? is false for rss_feed" do
    source = Source.new(kind: :rss_feed)
    item = Item.new(source: source)
    assert_not video?(item)
  end

  test "video? is false for generic_page" do
    source = Source.new(kind: :generic_page)
    item = Item.new(source: source)
    assert_not video?(item)
  end

  test "video? is false when source is nil" do
    item = Item.new(source: nil)
    assert_not video?(item)
  end
end
