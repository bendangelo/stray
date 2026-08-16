require "test_helper"

class LinkIntakeJobTest < ActiveJob::TestCase
  def setup
    @user = users(:one)
  end

  test "creates source + follow + items for YouTube channel URL" do
    contents = [
      Stray::ExtractedContent.new(
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
      LinkIntakeJob.perform_now(@user.id, "https://bitchute.com/video/bcvid123")
    end

    source = Source.find_by(external_id: "abc", user_id: @user.id)
    assert_not_nil source
    assert_equal "video_channel", source.kind
    assert_equal "BC Channel", source.name
    assert_equal 1.0, source.follows.first.weight
    assert_equal 1, source.items.count
  end

  test "broadcasts success via Turbo Stream" do
    content = Stray::ExtractedContent.new(
      title: "Video", content_text: nil, content_html: nil,
      thumbnail_url: nil, published_at: 1.day.ago,
      external_id: "v1", duration: nil,
      creator_identity: Stray::CreatorIdentity.new(
        name: "Chan", url: "https://bitchute.com/channel/abc",
        external_id: "abc", thumbnail_url: nil
      ),
      tags: []
    )

    extractor = Minitest::Mock.new
    extractor.expect(:extract, content, [ "https://bitchute.com/video/v1" ])

    broadcast_called = false
    Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*) { broadcast_called = true }) do
      Stray::ExtractorRegistry.stub(:find_for, extractor) do
        LinkIntakeJob.perform_now(@user.id, "https://bitchute.com/video/v1")
      end
    end

    assert broadcast_called
  end

  test "broadcasts error on extraction failure" do
    failing = Object.new
    failing.define_singleton_method(:extract) { |_url| raise Stray::YtDlp::ExtractionFailed, "failed" }

    broadcast_called = false
    Turbo::StreamsChannel.stub(:broadcast_replace_to, ->(*) { broadcast_called = true }) do
      Stray::ExtractorRegistry.stub(:find_for, failing) do
        LinkIntakeJob.perform_now(@user.id, "https://bitchute.com/video/v1")
      end
    end

    assert broadcast_called
  end

  test "applies extractor tags from single video" do
    content = Stray::ExtractedContent.new(
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
end
