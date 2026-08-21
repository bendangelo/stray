require "test_helper"

class SourceBackfillJobTest < ActiveJob::TestCase
  def setup
    @user = users(:one)
    @source = Source.create!(
      user: @user,
      kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCtest123",
      external_id: "UCtest123"
    )
  end

  def content(external_id, title, duration: nil, thumbnail_url: nil, published_at: nil)
    Stray::ExtractedContent.new(
      url: "https://example.com/watch?v=#{external_id}",
      title: title, content_text: "desc", content_html: nil,
      thumbnail_url: thumbnail_url, published_at: published_at,
      external_id: external_id, duration: duration, creator_identity: nil, tags: []
    )
  end

  test "skips when source has already been backfilled" do
    @source.update!(backfilled_at: 1.day.ago)
    extractor = Object.new
    extractor.define_singleton_method(:extract_backfill) { |_url, limit:| raise "should not be called" }

    Stray::BridgeRegistry.stub(:find_for_source, extractor) do
      assert_no_enqueued_jobs(only: EmbeddingJob) do
        SourceBackfillJob.perform_now(@source.id)
      end
    end
  end

  test "skips when bridge does not support backfill" do
    extractor = Object.new
    extractor.define_singleton_method(:extract_backfill) { |_url, limit:| nil }

    Stray::BridgeRegistry.stub(:find_for_source, extractor) do
      SourceBackfillJob.perform_now(@source.id)
    end

    assert_nil @source.reload.backfilled_at
  end

  test "upserts backfilled items and sets backfilled_at" do
    contents = [ content("vid1", "Video 1", duration: 120, thumbnail_url: "https://t.jpg", published_at: 1.day.ago) ]
    extractor = Object.new
    extractor.define_singleton_method(:extract_backfill) { |_url, limit:| contents }

    Stray::BridgeRegistry.stub(:find_for_source, extractor) do
      SourceBackfillJob.perform_now(@source.id)
    end

    @source.reload
    assert_equal 1, @source.items.count
    assert_equal "Video 1", @source.items.find_by(external_id: "vid1").title
    assert_not_nil @source.backfilled_at
  end

  test "does not create duplicates for items already present from RSS" do
    @source.items.create!(user: @user, external_id: "vid1", title: "Old", url: "https://example.com/v1", published_at: 1.day.ago)

    contents = [ content("vid1", "New Title", duration: 120, thumbnail_url: "https://t.jpg", published_at: 1.day.ago) ]
    extractor = Object.new
    extractor.define_singleton_method(:extract_backfill) { |_url, limit:| contents }

    Stray::BridgeRegistry.stub(:find_for_source, extractor) do
      SourceBackfillJob.perform_now(@source.id)
    end

    assert_equal 1, @source.items.count
    assert_equal "New Title", @source.items.find_by(external_id: "vid1").title
  end

  test "enqueues MetadataEnrichmentJob for items missing metadata" do
    contents = [ content("vid1", "No Duration") ]
    extractor = Object.new
    extractor.define_singleton_method(:extract_backfill) { |_url, limit:| contents }

    Stray::BridgeRegistry.stub(:find_for_source, extractor) do
      assert_enqueued_with(job: MetadataEnrichmentJob) do
        SourceBackfillJob.perform_now(@source.id)
      end
    end
  end

  test "skips non-existent source gracefully" do
    assert_nothing_raised do
      SourceBackfillJob.perform_now(99999)
    end
  end
end
