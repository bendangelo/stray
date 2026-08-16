require "test_helper"

class SourcePollFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def without_lock
    Stray::DomainMutex.stub(:with_lock, ->(_domain, &block) { block.call }) do
      yield
    end
  end

  test "full poll cycle: create source, poll, items appear" do
    user = users(:one)

    source = Source.create!(
      user: user,
      kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCtest123",
      external_id: "UCtest123",
      next_crawl_at: 1.hour.ago
    )

    contents = [
      Stray::ExtractedContent.new(
        title: "Integration Test Video", content_text: "Test description",
        content_html: nil, thumbnail_url: "https://example.com/t.jpg",
        published_at: 1.hour.ago, external_id: "inttest1", duration: 60,
        creator_identity: nil, tags: []
      )
    ]

    extractor = Minitest::Mock.new
    extractor.expect(:extract, contents, [ source.url ])

    Stray::ExtractorRegistry.stub(:find_for, extractor, [ source.url ]) do
      without_lock do
        SourcePollJob.perform_now(source.id)
      end
    end

    source.reload
    assert_equal 1, source.items.count
    assert_equal "Integration Test Video", source.items.first.title
    assert_not_nil source.last_polled_at
    assert_not_nil source.next_crawl_at
    assert source.next_crawl_at > Time.current
  end

  test "sweep enqueues poll jobs for due sources" do
    user = users(:one)

    Source.create!(
      user: user, kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsweep1",
      external_id: "UCsweep1", next_crawl_at: 1.hour.ago
    )
    Source.create!(
      user: user, kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsweep2",
      external_id: "UCsweep2", next_crawl_at: 1.hour.ago
    )

    assert_difference -> { enqueued_jobs.size }, 2 do
      SourcePollSweepJob.perform_now
    end

    enqueued_source_polls = enqueued_jobs.select { |j| j["job_class"] == "SourcePollJob" }
    assert_equal 2, enqueued_source_polls.size
  end
end
