class SourcePollSweepJob < ApplicationJob
  queue_as :default

  def perform
    clear_stale_polling_flags
    recover_abandoned_pending

    enqueue_poll(Source.due_for_poll)
    enqueue_poll(Source.recovering.where("next_crawl_at <= ? OR next_crawl_at IS NULL", Time.current))
    enqueue_poll(Source.stuck)
  end

  private

  def enqueue_poll(scope)
    scope.in_batches(of: 100) do |batch|
      batch.where(polling: false).each do |source|
        SourcePollJob.perform_later(source.id)
      end
    end
  end

  def clear_stale_polling_flags
    Source.where(polling: true).where("updated_at < ?", 10.minutes.ago).update_all(polling: false)
  end

  def recover_abandoned_pending
    Source.where(status: :pending)
      .where(polling: false)
      .where("last_polled_at IS NULL")
      .where("next_crawl_at IS NULL")
      .where("created_at < ?", 10.minutes.ago)
      .find_each do |source|
        Source::StatusMachine.recover_abandoned!(
          source,
          message: "Abandoned in pending — no poll completed within 10 minutes."
        )
      end
  end
end
