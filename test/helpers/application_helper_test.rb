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

  test "time_until returns empty string for nil" do
    assert_equal "", time_until(nil)
  end

  test "time_until returns in <1m for under a minute" do
    travel_to Time.current do
      assert_equal "in <1m", time_until(30.seconds.from_now)
    end
  end

  test "time_until returns in Xm for minutes" do
    travel_to Time.current do
      assert_equal "in 5m", time_until(5.minutes.from_now)
    end
  end

  test "time_until returns in Xh for hours" do
    travel_to Time.current do
      assert_equal "in 3h", time_until(3.hours.from_now)
    end
  end

  test "time_until returns in Xd for days" do
    travel_to Time.current do
      assert_equal "in 2d", time_until(2.days.from_now)
    end
  end

  test "time_until returns due now for past times" do
    travel_to Time.current do
      assert_equal "due now", time_until(30.seconds.ago)
    end
  end

  test "time_until returns formatted date for over a week" do
    travel_to Time.current do
      assert_equal 8.days.from_now.strftime("%b %d, %Y"), time_until(8.days.from_now)
    end
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

  test "embed_url constructs Odysee embed URL" do
    source = Source.new(kind: :odysee_channel)
    item = Item.new(source: source, url: "https://odysee.com/@samtime:1/apple-reacts-framework:f0bfe667")
    url = embed_url(item)
    assert_equal "https://odysee.com/$/embed/@samtime:1/apple-reacts-framework:f0bfe667", url
  end

  test "embed_url constructs Rumble embed URL from the URL slug" do
    source = Source.new(kind: :rumble_channel)
    item = Item.new(source: source, url: "https://rumble.com/v7a8neu-what-you-need-to-know.html")
    url = embed_url(item)
    assert_equal "https://rumble.com/embed/v7a8neu/", url
  end

  test "embed_url constructs PeerTube embed URL" do
    source = Source.new(kind: :peertube_channel)
    item = Item.new(source: source, url: "https://peertube.example.com/w/abc123", external_id: "abc123")
    url = embed_url(item)
    assert_equal "https://peertube.example.com/videos/embed/abc123", url
  end

  test "embed_url returns nil for unknown source kind" do
    source = Source.create!(user: users(:one), kind: :rss_feed, url: "https://example.com/feed", external_id: "feed1")
    item = Item.create!(source: source, user: users(:one), external_id: "e1", title: "Post", url: "https://example.com/post")

    assert_nil embed_url(item)
  end

  test "missing_thumb returns the missing-video asset path" do
    assert_match(/missing-video\.jpg/, missing_thumb)
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

  test "video? is true for rumble_channel" do
    source = Source.new(kind: :rumble_channel)
    item = Item.new(source: source)
    assert video?(item)
  end

  test "video? is true for bitchute_channel" do
    source = Source.new(kind: :bitchute_channel)
    item = Item.new(source: source)
    assert video?(item)
  end

  test "video? is true for odysee_channel" do
    source = Source.new(kind: :odysee_channel)
    item = Item.new(source: source)
    assert video?(item)
  end

  test "video? is true for peertube_channel" do
    source = Source.new(kind: :peertube_channel)
    item = Item.new(source: source)
    assert video?(item)
  end
end
