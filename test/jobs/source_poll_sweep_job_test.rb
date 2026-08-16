require "test_helper"

class SourcePollSweepJobTest < ActiveJob::TestCase
  test "enqueues SourcePollJob for due sources only" do
    due_source = Source.create!(
      user: users(:one), kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC1",
      external_id: "UC1", next_crawl_at: 1.hour.ago
    )
    not_due_source = Source.create!(
      user: users(:one), kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC2",
      external_id: "UC2", next_crawl_at: 1.hour.from_now
    )
    inactive_source = Source.create!(
      user: users(:one), kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC3",
      external_id: "UC3", next_crawl_at: 1.hour.ago, active: false
    )

    assert_enqueued_with(job: SourcePollJob, args: [ due_source.id ]) do
      SourcePollSweepJob.perform_now
    end

    poll_args = enqueued_jobs.select { |j| j["job_class"] == "SourcePollJob" }.map { |j| j["arguments"].first }
    assert_includes poll_args, due_source.id
    assert_not_includes poll_args, not_due_source.id
    assert_not_includes poll_args, inactive_source.id
  end

  test "handles empty due set without error" do
    assert_nothing_raised do
      SourcePollSweepJob.perform_now
    end
  end

  test "clears stale polling flags older than 10 minutes" do
    stale = Source.create!(
      user: users(:one), kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCstale",
      external_id: "UCstale", polling: true, updated_at: 20.minutes.ago
    )
    fresh = Source.create!(
      user: users(:one), kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCfresh",
      external_id: "UCfresh", polling: true, updated_at: 1.minute.ago
    )

    SourcePollSweepJob.perform_now

    assert_not stale.reload.polling?
    assert fresh.reload.polling?
  end
end
