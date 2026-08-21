require "test_helper"

class Youtube::PendingChannelResolverTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  def build_source(url:, external_id: "pending:x", status: :pending)
    Source.create!(user: @user, kind: :youtube_channel, url: url, external_id: external_id, status: status)
  end

  def resolver_result(channel_id: "UCResolved")
    Youtube::ChannelResolver::Result.new(
      channel_id: channel_id,
      rss_url: "https://www.youtube.com/feeds/videos.xml?channel_id=#{channel_id}",
      channel_name: "Resolved Channel",
      channel_url: "https://www.youtube.com/channel/#{channel_id}",
      channel_avatar_url: "https://yt3.ggpht.com/avatar"
    )
  end

  test "resolves a pending handle URL and marks source ok" do
    source = build_source(url: "https://www.youtube.com/@Handle")

    Youtube::ChannelResolver.stub(:resolve, resolver_result) do
      result = Youtube::PendingChannelResolver.call(source)
      assert_equal source, result
    end

    source.reload
    assert_equal "UCResolved", source.external_id
    assert_equal "https://www.youtube.com/feeds/videos.xml?channel_id=UCResolved", source.url
    assert_equal "Resolved Channel", source.name
    assert_equal "https://www.youtube.com/channel/UCResolved", source.channel_url
    assert_equal "https://yt3.ggpht.com/avatar", source.icon_url
    assert source.ok?
    assert_equal 0, source.recovery_attempts
    assert_not_nil source.last_polled_at
  end

  test "returns source unchanged when url is already an RSS feed" do
    source = build_source(
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCResolved",
      external_id: "UCResolved", status: :ok
    )

    result = Youtube::PendingChannelResolver.call(source)

    assert_equal source, result
    assert source.ok?
  end

  test "adopts existing channel on RecordNotUnique" do
    existing = Source.create!(user: @user, kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCResolved",
      external_id: "UCResolved", status: :ok)
    Follow.create!(user: @user, source: existing)

    source = build_source(url: "https://www.youtube.com/@Handle")
    Follow.create!(user: @user, source: source)

    Youtube::ChannelResolver.stub(:resolve, resolver_result) do
      result = Youtube::PendingChannelResolver.call(source)
      assert_equal existing, result
    end

    assert_not Source.exists?(source.id)
    assert_equal 1, existing.follows.count
  end

  test "re-raises YtDlp error" do
    source = build_source(url: "https://www.youtube.com/@Handle")

    Youtube::ChannelResolver.stub(:resolve, ->(_url) { raise Stray::YtDlp::Error, "yt-dlp failed" }) do
      assert_raises(Stray::YtDlp::Error) do
        Youtube::PendingChannelResolver.call(source)
      end
    end
  end

  test "marks source recovering on generic resolution error" do
    source = build_source(url: "https://www.youtube.com/@Handle")

    Youtube::ChannelResolver.stub(:resolve, ->(_url) { raise StandardError, "boom" }) do
      result = Youtube::PendingChannelResolver.call(source)
      assert_equal source, result
    end

    source.reload
    assert source.recovering?
    assert_equal "boom", source.last_error
    assert_equal 1, source.recovery_attempts
    assert_in_delta 1.minute, source.next_crawl_at - Time.current, 5.seconds
  end
end
