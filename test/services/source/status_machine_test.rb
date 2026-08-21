require "test_helper"

class Source::StatusMachineTest < ActiveSupport::TestCase
  setup do
    @source = Source.create!(user: users(:one), kind: :rss_feed,
      url: "https://example.com/feed", external_id: "x", status: :pending)
  end

  test "mark_ok! clears errors and resets recovery_attempts" do
    @source.update!(recovery_attempts: 3, last_error: "boom", last_error_at: 1.hour.ago)
    Source::StatusMachine.mark_ok!(@source, etag: "e", last_modified: "lm")
    assert @source.ok?
    assert_equal 0, @source.recovery_attempts
    assert_nil @source.last_error
    assert_not_nil @source.last_polled_at
    assert_equal "e", @source.etag
  end

  test "mark_degraded! resets recovery_attempts" do
    @source.update!(recovery_attempts: 2)
    Source::StatusMachine.mark_degraded!(@source)
    assert @source.degraded?
    assert_equal 0, @source.recovery_attempts
  end

  test "mark_recovering! increments attempts and applies backoff" do
    Source::StatusMachine.mark_recovering!(@source, message: "timeout")
    assert @source.recovering?
    assert_equal 1, @source.recovery_attempts
    assert_equal "timeout", @source.last_error
    assert_in_delta 1.minute, @source.next_crawl_at - Time.current, 5.seconds
    assert_not @source.polling
  end

  test "mark_recovering! caps backoff at 60 minutes" do
    @source.update!(recovery_attempts: 99)
    Source::StatusMachine.mark_recovering!(@source, message: "x")
    assert_in_delta 60.minutes, @source.next_crawl_at - Time.current, 5.seconds
    assert_equal 100, @source.recovery_attempts
  end

  test "mark_failed! sets next_crawl_at 5 minutes out" do
    Source::StatusMachine.mark_failed!(@source, message: "blocked")
    assert @source.failed?
    assert_in_delta 5.minutes, @source.next_crawl_at - Time.current, 5.seconds
    assert_not @source.polling
  end

  test "reset_for_poll! clears errors and sets pending" do
    @source.update!(status: :failed, last_error: "boom", next_crawl_at: 1.hour.from_now)
    Source::StatusMachine.reset_for_poll!(@source)
    assert @source.pending?
    assert @source.polling
    assert_nil @source.last_error
    assert_nil @source.next_crawl_at
  end
end
