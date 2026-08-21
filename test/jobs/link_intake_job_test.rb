require "test_helper"

class LinkIntakeJobTest < ActiveJob::TestCase
  def setup
    @user = users(:one)
  end

  test "creates source + follow + items for YouTube channel URL" do
    contents = [
      Stray::ExtractedContent.new(
        url: "https://www.youtube.com/watch?v=vid1",
        title: "Video 1", content_text: "Desc 1", content_html: nil,
        thumbnail_url: "https://example.com/t1.jpg", published_at: 1.day.ago,
        external_id: "vid1", duration: 120,
        creator_identity: Stray::CreatorIdentity.new(
          name: "Test Channel", url: "https://www.youtube.com/channel/UC123",
          external_id: "UC123", thumbnail_url: nil
        ),
        tags: []
      )
    ]

    resolver_result = Youtube::ChannelResolver::Result.new(
      channel_id: "UC123",
      rss_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC123",
      channel_name: "Test Channel",
      channel_url: "https://www.youtube.com/channel/UC123",
      channel_avatar_url: nil
    )

    extractor = Minitest::Mock.new
    extractor.expect(:extract, contents, [ resolver_result.rss_url ])

    Youtube::ChannelResolver.stub(:resolve, resolver_result) do
      Stray::BridgeRegistry.stub(:find_for, extractor, [ resolver_result.rss_url ]) do
        LinkIntakeJob.perform_now(@user.id, "https://www.youtube.com/channel/UC123")
      end
    end

    source = Source.find_by(external_id: "UC123", user_id: @user.id)
    assert_not_nil source
    assert_equal "youtube_channel", source.kind
    assert_equal resolver_result.rss_url, source.url
    assert_equal "Test Channel", source.name

    assert_not_nil source.follows.first
    assert_equal 1.0, source.follows.first.weight

    assert_equal 1, source.items.count
    assert_equal "Video 1", source.items.first.title
  end

  test "creates source + follow + single item for YouTube video URL" do
    video_content = Stray::ExtractedContent.new(
      url: "https://www.youtube.com/watch?v=vid123",
      title: "Test Video", content_text: "Desc", content_html: nil,
      thumbnail_url: "https://example.com/t.jpg", published_at: 1.day.ago,
      external_id: "vid123", duration: 300,
      creator_identity: Stray::CreatorIdentity.new(
        name: "Test Channel", url: "https://www.youtube.com/channel/UC123",
        external_id: "UC123", thumbnail_url: nil
      ),
      tags: []
    )

    oembed_result = Youtube::Oembed::Result.new(
      title: "Test Video",
      author_name: "Test Channel",
      author_url: "https://www.youtube.com/@TestChannel",
      thumbnail_url: "https://example.com/t.jpg",
      external_id: "vid123"
    )

    resolver_result = Youtube::ChannelResolver::Result.new(
      channel_id: "UC123",
      rss_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC123",
      channel_name: "Test Channel",
      channel_url: "https://www.youtube.com/channel/UC123",
      channel_avatar_url: nil
    )

    rss_contents = [ video_content ]
    rss_extractor = Minitest::Mock.new
    rss_extractor.expect(:extract, rss_contents, [ "https://www.youtube.com/feeds/videos.xml?channel_id=UC123" ])

    Youtube::Oembed.stub(:fetch, oembed_result) do
      Youtube::ChannelResolver.stub(:resolve, resolver_result) do
        Stray::BridgeRegistry.stub(:find_for, rss_extractor, [ resolver_result.rss_url ]) do
          LinkIntakeJob.perform_now(@user.id, "https://www.youtube.com/watch?v=vid123")
        end
      end
    end

    source = Source.find_by(external_id: "UC123", user_id: @user.id)
    assert_not_nil source
    assert_equal "youtube_channel", source.kind
    assert_equal "https://www.youtube.com/feeds/videos.xml?channel_id=UC123", source.url
    assert_equal 1.0, source.follows.first.weight
    assert_equal 1, source.items.count
  end

  test "creates source for non-YouTube video URL" do
    content = Stray::ExtractedContent.new(
      url: "https://bitchute.com/video/bcvid123",
      title: "Bitchute Video", content_text: "Desc", content_html: nil,
      thumbnail_url: "https://example.com/t.jpg", published_at: 1.day.ago,
      external_id: "bcvid123", duration: 300,
      creator_identity: Stray::CreatorIdentity.new(
        name: "BC Channel", url: "https://bitchute.com/channel/abc",
        external_id: "abc", thumbnail_url: nil
      ),
      tags: []
    )

    extractor = Minitest::Mock.new
    extractor.expect(:extract, content, [ "https://bitchute.com/video/bcvid123" ])

    Stray::BridgeRegistry.stub(:find_for, extractor) do
      assert_enqueued_with(job: SourcePollJob) do
        LinkIntakeJob.perform_now(@user.id, "https://bitchute.com/video/bcvid123")
      end
    end

    source = Source.find_by(external_id: "abc", user_id: @user.id)
    assert_not_nil source
    assert_equal "bitchute_channel", source.kind
    assert_equal "BC Channel", source.name
    assert_equal 1.0, source.follows.first.weight
    assert_equal 1, source.items.count
  end

  test "creates a generic_page source for a non-video URL without creator identity" do
    content = Stray::ExtractedContent.new(
      url: "https://example.com/blog/hello-world",
      title: "Hello World", content_text: "Body text", content_html: "<p>Body text</p>",
      thumbnail_url: nil, published_at: nil,
      external_id: Digest::SHA256.hexdigest("https://example.com/blog/hello-world")[0, 32],
      duration: nil,
      creator_identity: nil,
      tags: []
    )

    extractor = Minitest::Mock.new
    extractor.expect(:extract, content, [ "https://example.com/blog/hello-world" ])

    Bridges::GenericList.stub(:detect, nil) do
      Stray::BridgeRegistry.stub(:find_for, extractor) do
        LinkIntakeJob.perform_now(@user.id, "https://example.com/blog/hello-world")
      end
    end

    source = Source.find_by(kind: "generic_page", user_id: @user.id)
    assert_not_nil source
    assert_equal "https://example.com/blog/hello-world", source.url
    assert_equal "Hello World", source.name
    assert_equal 1, source.items.count
    assert_equal "Hello World", source.items.first.title
  end

  test "does not create a duplicate source when extraction fails with a pre-created source" do
    source = Source.create!(user: @user, kind: :video_channel,
      url: "https://bitchute.com/channel/abc", external_id: "abc")
    Follow.create!(user: @user, source: source)

    failing = Object.new
    failing.define_singleton_method(:extract_feed) { |_url| raise Stray::YtDlp::ExtractionFailed, "failed" }

    Stray::BridgeRegistry.stub(:find_for_source, failing) do
      LinkIntakeJob.perform_now(@user.id, "https://bitchute.com/channel/abc", source.id)
    end

    assert_equal 1, Source.where(external_id: "abc", user_id: @user.id).count
  end

  test "marks pre-created source as failed when a pending youtube channel cannot be resolved" do
    source = Source.create!(user: @user, kind: :youtube_channel,
      url: "https://www.youtube.com/@Unresolvable", external_id: "pending:u", status: :pending)
    Follow.create!(user: @user, source: source)

    Youtube::ChannelResolver.stub(:resolve, ->(_url) { raise Stray::YtDlp::Error, "yt-dlp failed" }) do
      LinkIntakeJob.perform_now(@user.id, "https://www.youtube.com/@Unresolvable", source.id)
    end

    source.reload
    assert source.failed?
    assert_equal "yt-dlp failed", source.last_error
  end

  test "marks source failed and enqueues poll when extract fails after resolution" do
    source = Source.create!(user: @user, kind: :youtube_channel,
      url: "https://www.youtube.com/@Handle", external_id: "pending:h", status: :pending)
    Follow.create!(user: @user, source: source)

    resolver_result = Youtube::ChannelResolver::Result.new(
      channel_id: "UCResolved",
      rss_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCResolved",
      channel_name: "Resolved Channel",
      channel_url: "https://www.youtube.com/channel/UCResolved",
      channel_avatar_url: nil
    )

    failing = Object.new
    failing.define_singleton_method(:extract_feed) { |_url| raise StandardError, "rss boom" }

    Youtube::ChannelResolver.stub(:resolve, resolver_result) do
      Stray::BridgeRegistry.stub(:find_for_source, failing) do
        assert_enqueued_with(job: SourcePollJob) do
          LinkIntakeJob.perform_now(@user.id, "https://www.youtube.com/@Handle", source.id)
        end
      end
    end

    source.reload
    assert source.failed?
    assert_equal "rss boom", source.last_error
    assert_equal "UCResolved", source.external_id
    assert_equal resolver_result.rss_url, source.url
    assert_equal 0, source.items.count
  end

  test "marks source failed via discard when YtDlp error raised after resolution" do
    source = Source.create!(user: @user, kind: :youtube_channel,
      url: "https://www.youtube.com/@Handle", external_id: "pending:h2", status: :pending)
    Follow.create!(user: @user, source: source)

    resolver_result = Youtube::ChannelResolver::Result.new(
      channel_id: "UCResolved2",
      rss_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCResolved2",
      channel_name: "Resolved Channel",
      channel_url: "https://www.youtube.com/channel/UCResolved2",
      channel_avatar_url: nil
    )

    failing = Object.new
    failing.define_singleton_method(:extract_feed) { |_url| raise Stray::YtDlp::Error, "yt-dlp boom" }

    Youtube::ChannelResolver.stub(:resolve, resolver_result) do
      Stray::BridgeRegistry.stub(:find_for_source, failing) do
        LinkIntakeJob.perform_now(@user.id, "https://www.youtube.com/@Handle", source.id)
      end
    end

    source.reload
    assert source.failed?
    assert_equal "yt-dlp boom", source.last_error
  end

  test "marks source failed via discard when extraction error raised after resolution" do
    source = Source.create!(user: @user, kind: :youtube_channel,
      url: "https://www.youtube.com/@Handle", external_id: "pending:h3", status: :pending)
    Follow.create!(user: @user, source: source)

    resolver_result = Youtube::ChannelResolver::Result.new(
      channel_id: "UCResolved3",
      rss_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCResolved3",
      channel_name: "Resolved Channel",
      channel_url: "https://www.youtube.com/channel/UCResolved3",
      channel_avatar_url: nil
    )

    failing = Object.new
    failing.define_singleton_method(:extract_feed) { |_url| raise Stray::ExtractionError, "youtube rss fetch failed: 404" }

    Youtube::ChannelResolver.stub(:resolve, resolver_result) do
      Stray::BridgeRegistry.stub(:find_for_source, failing) do
        LinkIntakeJob.perform_now(@user.id, "https://www.youtube.com/@Handle", source.id)
      end
    end

    source.reload
    assert source.failed?
    assert_equal "youtube rss fetch failed: 404", source.last_error
  end

  test "uses pre-created source when source_id is provided" do
    source = Source.create!(user: @user, kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCpre",
      external_id: "UCpre")
    Follow.create!(user: @user, source: source)

    contents = [
      Stray::ExtractedContent.new(
        url: "https://www.youtube.com/watch?v=pre1",
        title: "Pre Video", content_text: "desc", content_html: nil,
        thumbnail_url: nil, published_at: 1.day.ago,
        external_id: "pre1", duration: 120,
        creator_identity: Stray::CreatorIdentity.new(
          name: "Chan", url: "https://www.youtube.com/channel/UCpre",
          external_id: "UCpre", thumbnail_url: nil
        ),
        tags: []
      )
    ]

    extractor = Minitest::Mock.new
    extractor.expect(:extract_feed, contents, [ source.url ])

    Stray::BridgeRegistry.stub(:find_for_source, extractor) do
      LinkIntakeJob.perform_now(@user.id, "https://www.youtube.com/channel/UCpre", source.id)
    end

    assert_equal 1, Source.where(external_id: "UCpre", user_id: @user.id).count
    assert_equal 1, source.items.count
    assert_equal "Pre Video", source.items.first.title
  end

  test "applies extractor tags from single video" do
    content = Stray::ExtractedContent.new(
      url: "https://bitchute.com/video/tagvid1",
      title: "Tagged Video", content_text: "desc", content_html: nil,
      thumbnail_url: nil, published_at: 1.day.ago,
      external_id: "tagvid1", duration: 300,
      creator_identity: Stray::CreatorIdentity.new(
        name: "Chan", url: "https://bitchute.com/channel/abc",
        external_id: "abc", thumbnail_url: nil
      ),
      tags: [ "python", "tutorial" ]
    )

    extractor = Minitest::Mock.new
    extractor.expect(:extract, content, [ "https://bitchute.com/video/tagvid1" ])

    Stray::BridgeRegistry.stub(:find_for, extractor) do
      LinkIntakeJob.perform_now(@user.id, "https://bitchute.com/video/tagvid1")
    end

    tag = Tag.find_by(user: @user, name: "python")
    assert tag
    assert Tagging.joins(:item).where(tag: tag).exists?
  end

  test "resolves a pending youtube_channel source with a handle URL" do
    source = Source.create!(user: @user, kind: :youtube_channel,
      url: "https://www.youtube.com/@RickAstley", external_id: "pending:handle", status: :pending)
    Follow.create!(user: @user, source: source)

    resolver_result = Youtube::ChannelResolver::Result.new(
      channel_id: "UCResolved",
      rss_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCResolved",
      channel_name: "Resolved Channel",
      channel_url: "https://www.youtube.com/channel/UCResolved",
      channel_avatar_url: nil
    )

    contents = [
      Stray::ExtractedContent.new(
        url: "https://www.youtube.com/watch?v=res1",
        title: "Resolved Video", content_text: "desc", content_html: nil,
        thumbnail_url: nil, published_at: 1.day.ago,
        external_id: "res1", duration: 120,
        creator_identity: Stray::CreatorIdentity.new(
          name: "Resolved Channel", url: "https://www.youtube.com/channel/UCResolved",
          external_id: "UCResolved", thumbnail_url: nil
        ),
        tags: []
      )
    ]

    extractor = Minitest::Mock.new
    extractor.expect(:extract_feed, contents, [ resolver_result.rss_url ])

    Youtube::ChannelResolver.stub(:resolve, resolver_result) do
      Stray::BridgeRegistry.stub(:find_for_source, extractor) do
        LinkIntakeJob.perform_now(@user.id, "https://www.youtube.com/@RickAstley", source.id)
      end
    end

    source.reload
    assert_equal "UCResolved", source.external_id
    assert_equal resolver_result.rss_url, source.url
    assert_equal "Resolved Channel", source.name
    assert source.ok?
    assert_equal 1, source.items.count
  end

  test "backfills source name from RSS feed for /channel/UC... URL" do
    contents = [
      Stray::ExtractedContent.new(
        url: "https://www.youtube.com/watch?v=vid1",
        title: "Video 1", content_text: "Desc", content_html: nil,
        thumbnail_url: "https://example.com/t.jpg", published_at: 1.day.ago,
        external_id: "vid1", duration: 120,
        creator_identity: Stray::CreatorIdentity.new(
          name: "Channel From Feed", url: "https://www.youtube.com/channel/UC456",
          external_id: "UC456", thumbnail_url: nil
        ),
        tags: []
      )
    ]

    resolver_result = Youtube::ChannelResolver::Result.new(
      channel_id: "UC456",
      rss_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC456",
      channel_name: nil,
      channel_url: "https://www.youtube.com/channel/UC456",
      channel_avatar_url: nil
    )

    extractor = Minitest::Mock.new
    extractor.expect(:extract, contents, [ resolver_result.rss_url ])

    Youtube::ChannelResolver.stub(:resolve, resolver_result) do
      Stray::BridgeRegistry.stub(:find_for, extractor, [ resolver_result.rss_url ]) do
        LinkIntakeJob.perform_now(@user.id, "https://www.youtube.com/channel/UC456")
      end
    end

    source = Source.find_by(external_id: "UC456", user_id: @user.id)
    assert_equal "Channel From Feed", source.name
  end

  test "creates an rss_feed source for a pasted RSS feed URL" do
    contents = [
      Stray::ExtractedContent.new(
        url: "https://blog.example.com/post-1",
        title: "Post 1", content_text: "Body", content_html: "<p>Body</p>",
        thumbnail_url: nil, published_at: 1.day.ago,
        external_id: "post-1", duration: nil,
        creator_identity: Stray::CreatorIdentity.new(
          name: "Example Blog", url: "https://blog.example.com",
          external_id: "https://blog.example.com/feed", thumbnail_url: nil
        ),
        tags: []
      )
    ]

    extractor = Minitest::Mock.new
    extractor.expect(:extract_feed, contents, [ "https://blog.example.com/feed" ])

    Stray::BridgeRegistry.stub(:find_for, extractor, [ "https://blog.example.com/feed" ]) do
      assert_enqueued_with(job: SourcePollJob) do
        LinkIntakeJob.perform_now(@user.id, "https://blog.example.com/feed")
      end
    end

    source = Source.find_by(kind: "rss_feed", user_id: @user.id)
    assert_not_nil source
    assert_equal "https://blog.example.com/feed", source.url
    assert_equal "Example Blog", source.name
    assert_equal 1, source.items.count
  end

  test "creates a rumble_channel source from a channel URL" do
    contents = [
      Stray::ExtractedContent.new(
        url: "https://rumble.com/vvid1", title: "Video 1", content_text: nil, content_html: nil,
        thumbnail_url: "https://img.jpg", published_at: 1.day.ago,
        external_id: "vid1", duration: 100,
        creator_identity: Stray::CreatorIdentity.new(
          name: "Bright Insight", url: "https://rumble.com/c/BrightInsight",
          external_id: "BrightInsight", thumbnail_url: nil
        ),
        tags: []
      )
    ]

    extractor = Minitest::Mock.new
    extractor.expect(:extract_feed, contents, [ "https://rumble.com/c/BrightInsight" ])

    Stray::BridgeRegistry.stub(:find_for, extractor) do
      assert_enqueued_with(job: SourcePollJob) do
        LinkIntakeJob.perform_now(@user.id, "https://rumble.com/c/BrightInsight")
      end
    end

    source = Source.find_by(kind: "rumble_channel", user_id: @user.id)
    assert_not_nil source
    assert_equal "BrightInsight", source.external_id
    assert_equal "Bright Insight", source.name
    assert_equal 1, source.items.count
  end

  test "creates a saved_video source and does not poll when follow_channel is false" do
    content = Stray::ExtractedContent.new(
      url: "https://bitchute.com/video/bcvid1",
      title: "Some Video", content_text: "Desc", content_html: nil,
      thumbnail_url: "https://example.com/t.jpg", published_at: 1.day.ago,
      external_id: "bcvid1", duration: 300,
      creator_identity: Stray::CreatorIdentity.new(
        name: "Some Channel", url: "https://bitchute.com/channel/somechannel",
        external_id: "somechannel", thumbnail_url: nil
      ),
      tags: []
    )

    extractor = Minitest::Mock.new
    extractor.expect(:extract, content, [ "https://bitchute.com/video/bcvid1" ])

    Stray::BridgeRegistry.stub(:find_for, extractor) do
      assert_no_enqueued_jobs only: SourcePollJob do
        LinkIntakeJob.perform_now(@user.id, "https://bitchute.com/video/bcvid1", nil, follow_channel: false)
      end
    end

    source = Source.find_by(external_id: "bcvid1", user_id: @user.id)
    assert_not_nil source
    assert_equal "saved_video", source.kind
    assert_equal "https://bitchute.com/video/bcvid1", source.url
    assert_equal "Some Video", source.name
    assert_equal 1, source.items.count
  end

  test "follows the channel and polls when follow_channel is true" do
    content = Stray::ExtractedContent.new(
      url: "https://bitchute.com/video/bcvid2",
      title: "Video 2", content_text: "Desc", content_html: nil,
      thumbnail_url: "https://example.com/t.jpg", published_at: 1.day.ago,
      external_id: "bcvid2", duration: 300,
      creator_identity: Stray::CreatorIdentity.new(
        name: "BC Channel", url: "https://bitchute.com/channel/abc",
        external_id: "abc", thumbnail_url: nil
      ),
      tags: []
    )

    extractor = Minitest::Mock.new
    extractor.expect(:extract, content, [ "https://bitchute.com/video/bcvid2" ])

    Stray::BridgeRegistry.stub(:find_for, extractor) do
      assert_enqueued_with(job: SourcePollJob) do
        LinkIntakeJob.perform_now(@user.id, "https://bitchute.com/video/bcvid2", nil, follow_channel: true)
      end
    end

    source = Source.find_by(external_id: "abc", user_id: @user.id)
    assert_equal "bitchute_channel", source.kind
  end

  test "creates generic_list source when list page detected" do
    contents = [ Stray::ExtractedContent.new(url: "https://example.com/post-1", title: "Post 1", content_text: nil, content_html: nil,
      thumbnail_url: nil, published_at: nil, external_id: Digest::SHA256.hexdigest("https://example.com/post-1"), duration: nil, creator_identity: nil, tags: []) ]
    extractor = Minitest::Mock.new
    extractor.expect(:extract_feed, contents, [ "https://example.com/blog" ])

    Bridges::GenericList.stub(:detect, 5) do
      Stray::BridgeRegistry.stub(:find_for, extractor, [ "https://example.com/blog" ]) do
        perform_enqueued_jobs do
          LinkIntakeJob.perform_later(@user.id, "https://example.com/blog")
        end
      end
    end

    source = Source.find_by(url: "https://example.com/blog")
    assert source
    assert_equal "generic_list", source.kind
    assert_equal 1, source.items.count
  end

  test "retries when rate budget is exhausted" do
    failing = Object.new
    failing.define_singleton_method(:extract_feed) { |_url| raise Stray::RateBudgetExhausted, "Rate budget exhausted for example.com" }

    Bridges::GenericList.stub(:detect, 5) do
      Stray::BridgeRegistry.stub(:find_for, failing, [ "https://example.com/blog" ]) do
        assert_enqueued_with(job: LinkIntakeJob) do
          LinkIntakeJob.perform_now(@user.id, "https://example.com/blog")
        end
      end
    end
  end

  test "creates a peertube channel source with the API URL as source.url" do
    contents = [
      Stray::ExtractedContent.new(
        url: "https://tilvids.com/w/abc", title: "Vid", content_text: nil, content_html: nil,
        thumbnail_url: nil, published_at: 1.day.ago, external_id: "abc", duration: 120,
        creator_identity: Stray::CreatorIdentity.new(
          name: "Fedi", url: "https://tilvids.com/video-channels/fedi",
          external_id: "fedi", thumbnail_url: nil
        ),
        tags: []
      )
    ]

    extractor = Minitest::Mock.new
    extractor.expect(:extract_feed, contents, [ "https://tilvids.com/video-channels/fedi" ])

    Stray::BridgeRegistry.stub(:find_for, extractor, [ "https://tilvids.com/video-channels/fedi" ]) do
      Stray::BridgeRegistry.stub(:find_for_source, extractor) do
        assert_enqueued_with(job: SourcePollJob) do
          LinkIntakeJob.perform_now(@user.id, "https://tilvids.com/video-channels/fedi")
        end
      end
    end

    source = Source.find_by(external_id: "fedi", user_id: @user.id)
    assert_not_nil source
    assert_equal "peertube_channel", source.kind
    assert_equal "https://tilvids.com/api/v1/video-channels/fedi/videos?count=100", source.url
    assert_equal "https://tilvids.com/video-channels/fedi", source.channel_url
    assert_equal "Fedi", source.name
  end
end
