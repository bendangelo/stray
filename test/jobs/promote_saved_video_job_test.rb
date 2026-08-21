require "test_helper"

class PromoteSavedVideoJobTest < ActiveJob::TestCase
  def setup
    @user = users(:one)
  end

  def saved_video_source_with_item(url: "https://www.youtube.com/watch?v=jobvid1", external_id: "jobvid1")
    source = Source.create!(user: @user, kind: :saved_video, url: url, external_id: external_id, name: "Saved Video")
    item = Item.create!(source: source, user: @user, external_id: external_id,
      title: "Saved Video", url: url, content_text: "Desc",
      thumbnail_url: "https://example.com/t.jpg", duration: 200, published_at: 1.day.ago, state: 0)
    [ source, item ]
  end

  test "promotes a saved_video item to a youtube_channel source via oEmbed" do
    saved_source, item = saved_video_source_with_item

    oembed_result = Youtube::Oembed::Result.new(
      title: "Saved Video",
      author_name: "Test Channel",
      author_url: "https://www.youtube.com/@TestChannel",
      thumbnail_url: "https://example.com/t.jpg",
      external_id: "savevid1"
    )

    resolver_result = Youtube::ChannelResolver::Result.new(
      channel_id: "UC123",
      rss_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC123",
      channel_name: "Test Channel",
      channel_url: "https://www.youtube.com/channel/UC123",
      channel_avatar_url: nil
    )

    Youtube::Oembed.stub(:fetch, oembed_result) do
      Youtube::ChannelResolver.stub(:resolve, resolver_result) do
        assert_enqueued_with(job: SourcePollJob) do
          PromoteSavedVideoJob.perform_now(item.id)
        end
      end
    end

    channel_source = Source.find_by(kind: "youtube_channel", user_id: @user.id, external_id: "UC123")
    assert_not_nil channel_source
    assert_equal resolver_result.rss_url, channel_source.url
    assert_equal "Test Channel", channel_source.name
    assert Follow.exists?(user: @user, source: channel_source)

    item.reload
    assert_equal channel_source.id, item.source_id
    assert_equal "jobvid1", item.external_id
    assert_equal "Saved Video", item.title

    assert_not Source.exists?(saved_source.id)
  end

  test "promotes via yt-dlp fallback when oEmbed returns no author_url" do
    saved_source, item = saved_video_source_with_item

    content = Stray::ExtractedContent.new(
      url: "https://www.youtube.com/watch?v=savevid1",
      title: "Saved Video", content_text: "Desc", content_html: nil,
      thumbnail_url: "https://example.com/t.jpg", published_at: 1.day.ago,
      external_id: "savevid1", duration: 200,
      creator_identity: Stray::CreatorIdentity.new(
        name: "YtDlp Channel", url: "https://www.youtube.com/channel/UC456",
        external_id: "UC456", thumbnail_url: nil
      ),
      tags: []
    )

    extractor = Minitest::Mock.new
    extractor.expect(:extract, content, [ "https://www.youtube.com/watch?v=jobvid1" ])

    Youtube::Oembed.stub(:fetch, nil) do
      Bridges::YtDlp.stub(:new, extractor) do
        assert_enqueued_with(job: SourcePollJob) do
          PromoteSavedVideoJob.perform_now(item.id)
        end
      end
    end

    channel_source = Source.find_by(kind: "youtube_channel", user_id: @user.id, external_id: "UC456")
    assert_not_nil channel_source
    assert_equal "https://www.youtube.com/feeds/videos.xml?channel_id=UC456", channel_source.url
    assert_equal "YtDlp Channel", channel_source.name

    item.reload
    assert_equal channel_source.id, item.source_id

    assert_not Source.exists?(saved_source.id)
  end

  test "reuses existing youtube_channel source if user already follows it" do
    saved_source, item = saved_video_source_with_item

    existing_channel = Source.create!(user: @user, kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC123",
      external_id: "UC123", name: "Existing Channel", status: :ok)
    Follow.create!(user: @user, source: existing_channel)

    oembed_result = Youtube::Oembed::Result.new(
      title: "Saved Video", author_name: "Existing Channel",
      author_url: "https://www.youtube.com/@TestChannel",
      thumbnail_url: "https://example.com/t.jpg", external_id: "savevid1"
    )

    resolver_result = Youtube::ChannelResolver::Result.new(
      channel_id: "UC123",
      rss_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC123",
      channel_name: "Existing Channel",
      channel_url: "https://www.youtube.com/channel/UC123",
      channel_avatar_url: nil
    )

    Youtube::Oembed.stub(:fetch, oembed_result) do
      Youtube::ChannelResolver.stub(:resolve, resolver_result) do
        assert_no_difference -> { Source.where(kind: "youtube_channel", external_id: "UC123", user_id: @user.id).count } do
          PromoteSavedVideoJob.perform_now(item.id)
        end
      end
    end

    item.reload
    assert_equal existing_channel.id, item.source_id

    assert_not Source.exists?(saved_source.id)
  end

  test "preserves item state and taggings when reassigning" do
    saved_source, item = saved_video_source_with_item
    item.update!(state: :saved)
    tag = Tag.create!(user: @user, name: "test-tag")
    Tagging.create!(item: item, tag: tag, source: :user)

    oembed_result = Youtube::Oembed::Result.new(
      title: "Saved Video", author_name: "Test Channel",
      author_url: "https://www.youtube.com/@TestChannel",
      thumbnail_url: "https://example.com/t.jpg", external_id: "savevid1"
    )

    resolver_result = Youtube::ChannelResolver::Result.new(
      channel_id: "UC123",
      rss_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC123",
      channel_name: "Test Channel",
      channel_url: "https://www.youtube.com/channel/UC123",
      channel_avatar_url: nil
    )

    Youtube::Oembed.stub(:fetch, oembed_result) do
      Youtube::ChannelResolver.stub(:resolve, resolver_result) do
        PromoteSavedVideoJob.perform_now(item.id)
      end
    end

    item.reload
    assert item.saved?
    assert_equal 1, item.taggings.count
    assert_equal "test-tag", item.taggings.first.tag.name
  end

  test "does not delete saved_video source when channel resolution fails" do
    saved_source, item = saved_video_source_with_item

    failing_extractor = Object.new
    def failing_extractor.extract(_url)
      raise Stray::YtDlp::ExtractionFailed, "yt-dlp down"
    end

    Youtube::Oembed.stub(:fetch, ->(_url) { raise Stray::ExtractionError, "oEmbed down" }) do
      Bridges::YtDlp.stub(:new, failing_extractor) do
        PromoteSavedVideoJob.perform_now(item.id)
      end
    end

    assert Source.exists?(saved_source.id)
    item.reload
    assert_equal saved_source.id, item.source_id
  end

  test "returns early if item no longer exists" do
    assert_nothing_raised do
      PromoteSavedVideoJob.perform_now(99999)
    end
  end
end
