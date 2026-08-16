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

    resolver_result = Stray::Youtube::ChannelResolver::Result.new(
      channel_id: "UC123",
      rss_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC123",
      channel_name: "Test Channel",
      channel_url: "https://www.youtube.com/channel/UC123"
    )

    extractor = Minitest::Mock.new
    extractor.expect(:extract, contents, [ resolver_result.rss_url ])

    Stray::Youtube::ChannelResolver.stub(:resolve, resolver_result) do
      Stray::ExtractorRegistry.stub(:find_for, extractor, [ resolver_result.rss_url ]) do
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

    ytdlp_extractor = Minitest::Mock.new
    ytdlp_extractor.expect(:extract, video_content, [ "https://www.youtube.com/watch?v=vid123" ])

    rss_contents = [ video_content ]
    rss_extractor = Minitest::Mock.new
    rss_extractor.expect(:extract, rss_contents, [ "https://www.youtube.com/feeds/videos.xml?channel_id=UC123" ])

    Stray::ExtractorRegistry.stub(:find_for, ->(url) {
      if url.include?("feeds/videos.xml")
        rss_extractor
      else
        ytdlp_extractor
      end
    }) do
      LinkIntakeJob.perform_now(@user.id, "https://www.youtube.com/watch?v=vid123")
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

    Stray::ExtractorRegistry.stub(:find_for, extractor) do
      assert_enqueued_with(job: SourcePollJob) do
        LinkIntakeJob.perform_now(@user.id, "https://bitchute.com/video/bcvid123")
      end
    end

    source = Source.find_by(external_id: "abc", user_id: @user.id)
    assert_not_nil source
    assert_equal "video_channel", source.kind
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

    Stray::ExtractorRegistry.stub(:find_for, extractor) do
      LinkIntakeJob.perform_now(@user.id, "https://example.com/blog/hello-world")
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

    Stray::ExtractorRegistry.stub(:find_for_source, failing) do
      LinkIntakeJob.perform_now(@user.id, "https://bitchute.com/channel/abc", source.id)
    end

    assert_equal 1, Source.where(external_id: "abc", user_id: @user.id).count
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

    Stray::ExtractorRegistry.stub(:find_for_source, extractor) do
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

    Stray::ExtractorRegistry.stub(:find_for, extractor) do
      LinkIntakeJob.perform_now(@user.id, "https://bitchute.com/video/tagvid1")
    end

    tag = Tag.find_by(user: @user, name: "python")
    assert tag
    assert Tagging.joins(:item).where(tag: tag).exists?
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

    resolver_result = Stray::Youtube::ChannelResolver::Result.new(
      channel_id: "UC456",
      rss_url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC456",
      channel_name: nil,
      channel_url: "https://www.youtube.com/channel/UC456"
    )

    extractor = Minitest::Mock.new
    extractor.expect(:extract, contents, [ resolver_result.rss_url ])

    Stray::Youtube::ChannelResolver.stub(:resolve, resolver_result) do
      Stray::ExtractorRegistry.stub(:find_for, extractor, [ resolver_result.rss_url ]) do
        LinkIntakeJob.perform_now(@user.id, "https://www.youtube.com/channel/UC456")
      end
    end

    source = Source.find_by(external_id: "UC456", user_id: @user.id)
    assert_equal "Channel From Feed", source.name
  end
end
