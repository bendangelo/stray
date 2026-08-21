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
    Item.create!(
      user: users(:one), source: not_due_source, external_id: "i2",
      title: "Item 2", url: "https://example.com/2", published_at: 1.day.ago
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

  test "does not enqueue poll for a due saved_video source" do
    saved = Source.create!(
      user: users(:one), kind: :saved_video,
      url: "https://bitchute.com/video/bcvid1",
      external_id: "bcvid1", next_crawl_at: 1.hour.ago, active: true
    )

    SourcePollSweepJob.perform_now

    poll_args = enqueued_jobs.select { |j| j["job_class"] == "SourcePollJob" }.map { |j| j["arguments"].first }
    assert_not_includes poll_args, saved.id
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

  test "enqueues SourcePollJob for stuck sources with no items" do
    stuck_source = Source.create!(
      user: users(:one), kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UCstuck",
      external_id: "UCstuck", status: :ok, last_polled_at: 10.minutes.ago
    )
    healthy_source = Source.create!(
      user: users(:one), kind: :youtube_channel,
      url: "https://www.youtube.com/feeds/videos.xml?channel_id=UChealthy",
      external_id: "UChealthy", status: :ok, last_polled_at: 10.minutes.ago,
      next_crawl_at: 1.hour.from_now
    )
    Item.create!(
      user: users(:one), source: healthy_source, external_id: "ih",
      title: "Healthy", url: "https://example.com/h", published_at: 1.day.ago
    )

    SourcePollSweepJob.perform_now

    poll_args = enqueued_jobs.select { |j| j["job_class"] == "SourcePollJob" }.map { |j| j["arguments"].first }
    assert_includes poll_args, stuck_source.id
    assert_not_includes poll_args, healthy_source.id
  end

  test "recovers abandoned pending sources older than 10 minutes" do
    abandoned = Source.create!(user: users(:one), kind: :rss_feed,
      url: "https://example.com/a", external_id: "a", status: :pending,
      polling: false, created_at: 20.minutes.ago)
    fresh_pending = Source.create!(user: users(:one), kind: :rss_feed,
      url: "https://example.com/b", external_id: "b", status: :pending,
      polling: false, created_at: 2.minutes.ago)

    SourcePollSweepJob.perform_now

    assert abandoned.reload.recovering?
    assert fresh_pending.reload.pending?
  end

  test "does not recover a pending source that is still polling" do
    polling = Source.create!(user: users(:one), kind: :rss_feed,
      url: "https://example.com/p", external_id: "p", status: :pending,
      polling: true, created_at: 20.minutes.ago)

    SourcePollSweepJob.perform_now

    assert polling.reload.pending?
  end

  test "enqueues poll for recovering sources whose next_crawl_at is due" do
    due = Source.create!(user: users(:one), kind: :rss_feed,
      url: "https://example.com/d", external_id: "d", status: :recovering,
      next_crawl_at: 5.minutes.ago, polling: false)
    not_due = Source.create!(user: users(:one), kind: :rss_feed,
      url: "https://example.com/n", external_id: "n", status: :recovering,
      next_crawl_at: 30.minutes.from_now, polling: false)

    SourcePollSweepJob.perform_now

    poll_args = enqueued_jobs.select { |j| j["job_class"] == "SourcePollJob" }.map { |j| j["arguments"].first }
    assert_includes poll_args, due.id
    assert_not_includes poll_args, not_due.id
  end
end
