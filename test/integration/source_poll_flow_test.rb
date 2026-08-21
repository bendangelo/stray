require "test_helper"

class SourcePollFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def without_lock
    DomainMutex.stub(:with_lock, ->(_domain, &block) { block.call }) do
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
        url: "https://example.com/watch?v=inttest1",
        title: "Integration Test Video", content_text: "Test description",
        content_html: nil, thumbnail_url: "https://example.com/t.jpg",
        published_at: 1.hour.ago, external_id: "inttest1", duration: 60,
        creator_identity: nil, tags: []
      )
    ]

    extractor = Minitest::Mock.new
    extractor.expect(:extract_feed, contents, [ source.url ])

    Stray::BridgeRegistry.stub(:find_for_source, extractor) do
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

    s1 = Source.create!(
      user: user, kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsweep1",
      external_id: "UCsweep1", next_crawl_at: 1.hour.ago
    )
    s2 = Source.create!(
      user: user, kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCsweep2",
      external_id: "UCsweep2", next_crawl_at: 1.hour.ago
    )
    Item.create!(user: user, source: s1, external_id: "s1", title: "S1", url: "https://example.com/s1", published_at: 1.day.ago)
    Item.create!(user: user, source: s2, external_id: "s2", title: "S2", url: "https://example.com/s2", published_at: 1.day.ago)

    SourcePollSweepJob.perform_now

    poll_args = enqueued_jobs.select { |j| j["job_class"] == "SourcePollJob" }.map { |j| j["arguments"].first }
    assert_includes poll_args, s1.id
    assert_includes poll_args, s2.id
  end
end
