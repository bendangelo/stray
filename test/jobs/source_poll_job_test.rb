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
        title: "Video 1", content_text: "Desc 1", content_html: nil,
        thumbnail_url: "https://example.com/t1.jpg", published_at: 1.day.ago,
        external_id: "vid1", duration: 120, creator_identity: nil, tags: [],
      ),
      Stray::ExtractedContent.new(
        title: "Video 2", content_text: "Desc 2", content_html: nil,
        thumbnail_url: "https://example.com/t2.jpg", published_at: 2.days.ago,
        external_id: "vid2", duration: 180, creator_identity: nil, tags: []
      )
    ]

    @extractor.expect(:extract, contents, [ @source.url ])

    Stray::ExtractorRegistry.stub(:find_for, @extractor, [ @source.url ]) do
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
        title: "New Title", content_text: "Updated", content_html: nil,
        thumbnail_url: nil, published_at: 1.day.ago,
        external_id: "vid1", duration: nil, creator_identity: nil, tags: []
      )
    ]

    @extractor.expect(:extract, contents, [ @source.url ])

    Stray::ExtractorRegistry.stub(:find_for, @extractor, [ @source.url ]) do
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
    failing.define_singleton_method(:extract) { |_url| raise Stray::YtDlp::ExtractionFailed, "yt-dlp failed" }

    Stray::ExtractorRegistry.stub(:find_for, failing, [ @source.url ]) do
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
        title: "Tagged Video", content_text: "desc", content_html: nil,
        thumbnail_url: nil, published_at: Time.current, external_id: "tagvid1",
        duration: nil, creator_identity: nil, tags: [ "ruby", "education" ]
      )
    ]

    @extractor.expect(:extract, contents, [ @source.url ])

    Stray::ExtractorRegistry.stub(:find_for, @extractor, [ @source.url ]) do
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
        title: "New Vid", content_text: "desc", content_html: nil,
        thumbnail_url: nil, published_at: Time.current, external_id: "newvid1",
        duration: nil, creator_identity: nil, tags: []
      )
    ]

    @extractor.expect(:extract, contents, [ @source.url ])

    Stray::ExtractorRegistry.stub(:find_for, @extractor, [ @source.url ]) do
      without_lock do
        assert_enqueued_with(job: EmbeddingJob) do
          SourcePollJob.perform_now(@source.id)
        end
      end
    end
  end
end
