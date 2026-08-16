require "test_helper"

class SourcePollJobTest < ActiveJob::TestCase
  def setup
    @user = users(:one)
    @source = Source.create!(
      user: @user,
      kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCtest123",
      external_id: "UCtest123"
    )
    @verify_extractor = true
    @extractor = Minitest::Mock.new
  end

  def teardown
    @extractor.verify if @verify_extractor
  end

  def without_lock
    Stray::DomainMutex.stub(:with_lock, ->(_domain, &block) { block.call }) do
      yield
    end
  end

  test "performs poll: extracts items, upserts, recalculates cadence" do
    contents = [
      Stray::ExtractedContent.new(
        url: "https://example.com/watch?v=vid1",
        title: "Video 1", content_text: "Desc 1", content_html: nil,
        thumbnail_url: "https://example.com/t1.jpg", published_at: 1.day.ago,
        external_id: "vid1", duration: 120, creator_identity: nil, tags: [],
      ),
      Stray::ExtractedContent.new(
        url: "https://example.com/watch?v=vid2",
        title: "Video 2", content_text: "Desc 2", content_html: nil,
        thumbnail_url: "https://example.com/t2.jpg", published_at: 2.days.ago,
        external_id: "vid2", duration: 180, creator_identity: nil, tags: []
      )
    ]

    @extractor.expect(:extract_feed, contents, [ @source.url ])

    Stray::ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    @source.reload
    assert_equal 2, @source.items.count
    assert_equal "Video 1", @source.items.find_by(external_id: "vid1").title
    assert_equal "Video 2", @source.items.find_by(external_id: "vid2").title
    assert_not_nil @source.last_polled_at
    assert_not_nil @source.next_crawl_at
    assert_nil @source.last_error
  end

  test "does not create duplicate items on re-poll" do
    @source.items.create!(
      user: @user, external_id: "vid1", title: "Old Title", url: "https://example.com/v1",
      published_at: 1.day.ago
    )

    contents = [
      Stray::ExtractedContent.new(
        url: "https://example.com/watch?v=vid1",
        title: "New Title", content_text: "Updated", content_html: nil,
        thumbnail_url: nil, published_at: 1.day.ago,
        external_id: "vid1", duration: nil, creator_identity: nil, tags: []
      )
    ]

    @extractor.expect(:extract_feed, contents, [ @source.url ])

    Stray::ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    assert_equal 1, @source.items.count
    assert_equal "New Title", @source.items.find_by(external_id: "vid1").title
  end

  test "records error on extraction failure" do
    @verify_extractor = false
    failing = Object.new
    failing.define_singleton_method(:extract_feed) { |_url| raise Stray::YtDlp::ExtractionFailed, "yt-dlp failed" }

    Stray::ExtractorRegistry.stub(:find_for_source, failing) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    @source.reload
    assert_equal "yt-dlp failed", @source.last_error
    assert_not_nil @source.last_error_at
  end

  test "skips non-existent source gracefully" do
    assert_nothing_raised do
      SourcePollJob.perform_now(99999)
    end
  end

  test "applies extractor tags to items" do
    contents = [
      Stray::ExtractedContent.new(
        url: "https://example.com/watch?v=tagvid1",
        title: "Tagged Video", content_text: "desc", content_html: nil,
        thumbnail_url: nil, published_at: Time.current, external_id: "tagvid1",
        duration: nil, creator_identity: nil, tags: [ "ruby", "education" ]
      )
    ]

    @extractor.expect(:extract_feed, contents, [ @source.url ])

    Stray::ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    item = Item.find_by(source: @source, external_id: "tagvid1")
    assert item
    ruby_tag = Tag.find_by(user: @user, name: "ruby")
    assert ruby_tag
    assert Tagging.find_by(item: item, tag: ruby_tag, source: :user)
  end

  test "enqueues EmbeddingJob for new items" do
    contents = [
      Stray::ExtractedContent.new(
        url: "https://example.com/watch?v=newvid1",
        title: "New Vid", content_text: "desc", content_html: nil,
        thumbnail_url: nil, published_at: Time.current, external_id: "newvid1",
        duration: nil, creator_identity: nil, tags: []
      )
    ]

    @extractor.expect(:extract_feed, contents, [ @source.url ])

    Stray::ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        assert_enqueued_with(job: EmbeddingJob) do
          SourcePollJob.perform_now(@source.id)
        end
      end
    end
  end

  test "backfills source name from creator_identity when name is nil" do
    @source.update!(name: nil)
    contents = [
      Stray::ExtractedContent.new(
        url: "https://example.com/watch?v=vid_name1",
        title: "Video", content_text: "desc", content_html: nil,
        thumbnail_url: nil, published_at: Time.current, external_id: "vid_name1",
        duration: nil,
        creator_identity: Stray::CreatorIdentity.new(
          name: "Backfilled Channel", url: "https://example.com",
          external_id: "UCtest", thumbnail_url: nil
        ),
        tags: []
      )
    ]

    @extractor.expect(:extract_feed, contents, [ @source.url ])

    Stray::ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    @source.reload
    assert_equal "Backfilled Channel", @source.name
  end

  test "records error when extractor does not implement extract_feed" do
    @verify_extractor = false
    extractor = Object.new
    extractor.define_singleton_method(:extract_feed) { |_url| raise NotImplementedError, "not implemented" }

    Stray::ExtractorRegistry.stub(:find_for_source, extractor) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    @source.reload
    assert_not_nil @source.last_error
    assert_match(/extract_feed/, @source.last_error)
  end

  test "clears polling flag after successful poll" do
    contents = [
      Stray::ExtractedContent.new(
        url: "https://example.com/watch?v=pollvid1",
        title: "Poll Vid", content_text: "desc", content_html: nil,
        thumbnail_url: "https://example.com/t.jpg", published_at: Time.current,
        external_id: "pollvid1", duration: nil, creator_identity: nil, tags: []
      )
    ]

    @extractor.expect(:extract_feed, contents, [ @source.url ])

    Stray::ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    @source.reload
    assert_not @source.polling?
  end

  test "clears polling flag even when extraction fails" do
    @verify_extractor = false
    failing = Object.new
    failing.define_singleton_method(:extract_feed) { |_url| raise Stray::YtDlp::ExtractionFailed, "boom" }

    Stray::ExtractorRegistry.stub(:find_for_source, failing) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    @source.reload
    assert_not @source.polling?
    assert_equal "boom", @source.last_error
  end

  test "enqueues ThumbnailEnrichmentJob for items missing thumbnails" do
    contents = [
      Stray::ExtractedContent.new(
        url: "https://example.com/watch?v=nothumb1",
        title: "No Thumb", content_text: "desc", content_html: nil,
        thumbnail_url: nil, published_at: Time.current, external_id: "nothumb1",
        duration: nil, creator_identity: nil, tags: []
      )
    ]

    @extractor.expect(:extract_feed, contents, [ @source.url ])

    Stray::ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        assert_enqueued_with(job: ThumbnailEnrichmentJob) do
          SourcePollJob.perform_now(@source.id)
        end
      end
    end
  end
end
