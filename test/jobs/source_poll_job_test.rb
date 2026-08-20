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
    DomainMutex.stub(:with_lock, ->(_domain, &block) { block.call }) do
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

    ExtractorRegistry.stub(:find_for_source, @extractor) do
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

    ExtractorRegistry.stub(:find_for_source, @extractor) do
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

    ExtractorRegistry.stub(:find_for_source, failing) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    @source.reload
    assert_equal "yt-dlp failed", @source.last_error
    assert_not_nil @source.last_error_at
  end

  test "records status-bearing error on extraction error" do
    @verify_extractor = false
    failing = Object.new
    failing.define_singleton_method(:extract_feed) { |_url| raise Stray::ExtractionError, "youtube rss fetch failed: 404" }

    ExtractorRegistry.stub(:find_for_source, failing) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    @source.reload
    assert_equal "youtube rss fetch failed: 404", @source.last_error
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

    ExtractorRegistry.stub(:find_for_source, @extractor) do
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

    ExtractorRegistry.stub(:find_for_source, @extractor) do
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

    ExtractorRegistry.stub(:find_for_source, @extractor) do
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

    ExtractorRegistry.stub(:find_for_source, extractor) do
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

    ExtractorRegistry.stub(:find_for_source, @extractor) do
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

    ExtractorRegistry.stub(:find_for_source, failing) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    @source.reload
    assert_not @source.polling?
    assert_equal "boom", @source.last_error
  end

  test "does not clobber existing duration when re-poll returns nil duration" do
    item = @source.items.create!(
      user: @user, external_id: "durvid1", title: "With Duration",
      url: "https://example.com/watch?v=durvid1", published_at: 1.day.ago,
      duration: 300
    )

    contents = [
      Stray::ExtractedContent.new(
        url: "https://example.com/watch?v=durvid1",
        title: "Updated Title", content_text: "desc", content_html: nil,
        thumbnail_url: nil, published_at: 1.day.ago, external_id: "durvid1",
        duration: nil, creator_identity: nil, tags: []
      )
    ]

    @extractor.expect(:extract_feed, contents, [ @source.url ])

    ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    assert_equal 300, item.reload.duration
    assert_equal "Updated Title", item.reload.title
  end

  test "does not clobber existing published_at when re-poll returns nil published_at" do
    item = @source.items.create!(
      user: @user, external_id: "pubvid1", title: "With Date",
      url: "https://example.com/watch?v=pubvid1", published_at: 1.day.ago,
      duration: 300
    )

    contents = [
      Stray::ExtractedContent.new(
        url: "https://example.com/watch?v=pubvid1",
        title: "Updated Title", content_text: "desc", content_html: nil,
        thumbnail_url: nil, published_at: nil, external_id: "pubvid1",
        duration: nil, creator_identity: nil, tags: []
      )
    ]

    @extractor.expect(:extract_feed, contents, [ @source.url ])

    ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    assert_equal 1.day.ago.to_i, item.reload.published_at.to_i
    assert_equal 300, item.reload.duration
  end

  test "enqueues MetadataEnrichmentJob for items missing duration" do
    contents = [
      Stray::ExtractedContent.new(
        url: "https://example.com/watch?v=nodur1",
        title: "No Duration", content_text: "desc", content_html: nil,
        thumbnail_url: "https://example.com/t.jpg", published_at: Time.current,
        external_id: "nodur1", duration: nil, creator_identity: nil, tags: []
      )
    ]

    @extractor.expect(:extract_feed, contents, [ @source.url ])

    ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        assert_enqueued_with(job: MetadataEnrichmentJob) do
          SourcePollJob.perform_now(@source.id)
        end
      end
    end
  end

  test "enqueues MetadataEnrichmentJob for items missing thumbnails" do
    contents = [
      Stray::ExtractedContent.new(
        url: "https://example.com/watch?v=nothumb1",
        title: "No Thumb", content_text: "desc", content_html: nil,
        thumbnail_url: nil, published_at: Time.current, external_id: "nothumb1",
        duration: nil, creator_identity: nil, tags: []
      )
    ]

    @extractor.expect(:extract_feed, contents, [ @source.url ])

    ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        assert_enqueued_with(job: MetadataEnrichmentJob) do
          SourcePollJob.perform_now(@source.id)
        end
      end
    end
  end

  test "enqueues MetadataEnrichmentJob for items missing published_at" do
    contents = [
      Stray::ExtractedContent.new(
        url: "https://example.com/watch?v=nopub1",
        title: "No Publish Date", content_text: "desc", content_html: nil,
        thumbnail_url: "https://example.com/t.jpg", published_at: nil,
        external_id: "nopub1", duration: nil, creator_identity: nil, tags: []
      )
    ]

    @extractor.expect(:extract_feed, contents, [ @source.url ])

    ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        assert_enqueued_with(job: MetadataEnrichmentJob) do
          SourcePollJob.perform_now(@source.id)
        end
      end
    end
  end

  test "enqueues next page when FeedResult has_more true" do
    source = Source.create!(user: @user, kind: :stray_collection,
      url: "https://stray.example.com/c/x/manifest.json", external_id: "x")
    Follow.create!(user: @user, source: source)
    RemoteCollection.create!(source: source, user: @user, manifest_url: source.url)

    items = [ Stray::ExtractedContent.new(url: "https://x/1", title: "T1", content_text: nil,
      content_html: nil, thumbnail_url: nil, published_at: Time.current, external_id: "i1",
      duration: nil, creator_identity: nil, tags: []) ]
    feed_result = Extractor::FeedResult.new(items: items, next_cursor: "cur2", has_more: true)

    @extractor.expect(:extract_feed, feed_result, [ source.url ])
    @verify_extractor = true

    ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        assert_enqueued_with(job: SourcePollJob, args: [ source.id, "cur2" ]) do
          SourcePollJob.perform_now(source.id)
        end
      end
    end
  end

  test "updates RemoteCollection after full sync" do
    source = Source.create!(user: @user, kind: :stray_collection,
      url: "https://stray.example.com/c/x/manifest.json", external_id: "x")
    Follow.create!(user: @user, source: source)
    rc = RemoteCollection.create!(source: source, user: @user, manifest_url: source.url)

    items = [ Stray::ExtractedContent.new(url: "https://x/1", title: "T1", content_text: nil,
      content_html: nil, thumbnail_url: nil, published_at: Time.current, external_id: "i1",
      duration: nil, creator_identity: nil, tags: []) ]
    feed_result = Extractor::FeedResult.new(items: items, next_cursor: nil, has_more: false)

    @extractor.expect(:extract_feed, feed_result, [ source.url ])

    ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        SourcePollJob.perform_now(source.id)
      end
    end

    rc.reload
    assert_not_nil rc.last_synced_at
    assert_equal 1, rc.item_count
    assert_nil rc.last_error
  end

  test "populates collection metadata and source name from FeedResult" do
    source = Source.create!(user: @user, kind: :stray_collection,
      url: "https://stray.example.com/c/x/manifest.json", external_id: "x", name: "Remote collection")
    Follow.create!(user: @user, source: source)
    rc = RemoteCollection.create!(source: source, user: @user, manifest_url: source.url)

    items = [ Stray::ExtractedContent.new(url: "https://x/1", title: "T1", content_text: nil,
      content_html: nil, thumbnail_url: nil, published_at: Time.current, external_id: "i1",
      duration: nil, creator_identity: nil, tags: []) ]
    feed_result = Extractor::FeedResult.new(items: items, next_cursor: nil, has_more: false,
      collection_name: "Econ", producer_instance_name: "Alice")

    @extractor.expect(:extract_feed, feed_result, [ source.url ])

    ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        SourcePollJob.perform_now(source.id)
      end
    end

    rc.reload
    assert_equal "Econ", rc.collection_name
    assert_equal "Alice", rc.producer_instance_name
    source.reload
    assert_equal "Econ", source.name
  end

  test "early stops when page contains only known external_ids" do
    source = Source.create!(user: @user, kind: :stray_collection,
      url: "https://stray.example.com/c/x/manifest.json", external_id: "x")
    Follow.create!(user: @user, source: source)
    RemoteCollection.create!(source: source, user: @user, manifest_url: source.url)
    source.items.create!(user: @user, external_id: "known1", title: "Old",
      url: "https://x/1", published_at: 1.day.ago, state: 0)

    items = [ Stray::ExtractedContent.new(url: "https://x/1", title: "Old", content_text: nil,
      content_html: nil, thumbnail_url: nil, published_at: 1.day.ago, external_id: "known1",
      duration: nil, creator_identity: nil, tags: []) ]
    feed_result = Extractor::FeedResult.new(items: items, next_cursor: "cur2", has_more: true)

    @extractor.expect(:extract_feed, feed_result, [ source.url ])

    ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        assert_no_enqueued_jobs(only: SourcePollJob) do
          SourcePollJob.perform_now(source.id)
        end
      end
    end
  end

  test "records RemoteCollection error on fetch failure" do
    source = Source.create!(user: @user, kind: :stray_collection,
      url: "https://stray.example.com/c/x/manifest.json", external_id: "x")
    Follow.create!(user: @user, source: source)
    rc = RemoteCollection.create!(source: source, user: @user, manifest_url: source.url)
    @verify_extractor = false

    failing = Object.new
    failing.define_singleton_method(:extract_feed) { |_url| raise UrlGuard::Blocked, "blocked" }

    ExtractorRegistry.stub(:find_for_source, failing) do
      without_lock do
        SourcePollJob.perform_now(source.id)
      end
    end

    rc.reload
    assert_not_nil rc.last_error
    assert_not_nil rc.last_error_at
  end

  test "sets status to ok on successful poll" do
    @source.update!(status: :pending)
    contents = [
      Stray::ExtractedContent.new(
        url: "https://example.com/watch?v=st1", title: "Video 1",
        content_text: "desc", content_html: nil, thumbnail_url: nil,
        published_at: 1.day.ago, external_id: "st1", duration: 120,
        creator_identity: nil, tags: []
      )
    ]

    @extractor.expect(:extract_feed, contents, [ @source.url ])
    ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    @source.reload
    assert @source.ok?
  end

  test "sets status to failed when extraction fails" do
    @source.update!(status: :pending)
    @verify_extractor = false
    failing = Object.new
    failing.define_singleton_method(:extract_feed) { |_url| raise NotImplementedError, "nope" }

    ExtractorRegistry.stub(:find_for_source, failing) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    @source.reload
    assert @source.failed?
    assert_not_nil @source.last_error
  end

  test "records error and reschedules on generic StandardError" do
    @source.update!(status: :ok, last_error: nil, next_crawl_at: 1.hour.from_now)
    @verify_extractor = false
    failing = Object.new
    failing.define_singleton_method(:extract_feed) { |_url| raise Faraday::TimeoutError, "timed out" }

    ExtractorRegistry.stub(:find_for_source, failing) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    @source.reload
    assert @source.failed?
    assert_equal "timed out", @source.last_error
    assert_not_nil @source.last_error_at
    assert @source.next_crawl_at <= 5.minutes.from_now
    assert @source.next_crawl_at > Time.current
  end

  test "reschedules next_crawl_at on NotImplementedError failure" do
    @source.update!(status: :ok, next_crawl_at: 1.hour.from_now)
    @verify_extractor = false
    failing = Object.new
    failing.define_singleton_method(:extract_feed) { |_url| raise NotImplementedError, "nope" }

    ExtractorRegistry.stub(:find_for_source, failing) do
      without_lock do
        SourcePollJob.perform_now(@source.id)
      end
    end

    @source.reload
    assert @source.failed?
    assert @source.next_crawl_at <= 5.minutes.from_now
    assert @source.next_crawl_at > Time.current
  end

  test "sets status to ok on successful relay sync" do
    source = Source.create!(user: @user, kind: :stray_collection,
      url: "https://stray.example.com/c/x/manifest.json", external_id: "x", status: :pending)
    Follow.create!(user: @user, source: source)
    RemoteCollection.create!(source: source, user: @user, manifest_url: source.url)

    items = [ Stray::ExtractedContent.new(url: "https://x/1", title: "T1", content_text: nil,
      content_html: nil, thumbnail_url: nil, published_at: Time.current, external_id: "i1",
      duration: nil, creator_identity: nil, tags: []) ]
    feed_result = Extractor::FeedResult.new(items: items, next_cursor: nil, has_more: false)

    @extractor.expect(:extract_feed, feed_result, [ source.url ])

    ExtractorRegistry.stub(:find_for_source, @extractor) do
      without_lock do
        SourcePollJob.perform_now(source.id)
      end
    end

    source.reload
    assert source.ok?
  end

  test "sets status to failed and reschedules on relay error" do
    source = Source.create!(user: @user, kind: :stray_collection,
      url: "https://stray.example.com/c/x/manifest.json", external_id: "x", status: :pending)
    Follow.create!(user: @user, source: source)
    RemoteCollection.create!(source: source, user: @user, manifest_url: source.url)
    @verify_extractor = false

    failing = Object.new
    failing.define_singleton_method(:extract_feed) { |_url| raise UrlGuard::Blocked, "blocked" }

    ExtractorRegistry.stub(:find_for_source, failing) do
      without_lock do
        SourcePollJob.perform_now(source.id)
      end
    end

    source.reload
    assert source.failed?
    assert_equal "blocked", source.last_error
    assert source.next_crawl_at <= 5.minutes.from_now
    assert source.next_crawl_at > Time.current
  end

  test "resolves a pending youtube channel handle URL before polling" do
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

    contents = [
      Stray::ExtractedContent.new(
        url: "https://example.com/watch?v=rp1", title: "V1",
        content_text: "desc", content_html: nil, thumbnail_url: nil,
        published_at: 1.day.ago, external_id: "rp1", duration: 120,
        creator_identity: nil, tags: []
      )
    ]

    @extractor.expect(:extract_feed, contents, [ resolver_result.rss_url ])

    Youtube::ChannelResolver.stub(:resolve, resolver_result) do
      ExtractorRegistry.stub(:find_for_source, @extractor) do
        without_lock do
          SourcePollJob.perform_now(source.id)
        end
      end
    end

    source.reload
    assert_equal "UCResolved", source.external_id
    assert_equal resolver_result.rss_url, source.url
    assert source.ok?
    assert_equal 1, source.items.count
  end
end
