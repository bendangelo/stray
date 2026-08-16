class SourcePollSweepJob < ApplicationJob
  queue_as :default

  def perform
    clear_stale_polling_flags

    Source.due_for_poll.in_batches(of: 100) do |batch|
      batch.each do |source|
        SourcePollJob.perform_later(source.id)
      end
    end
  end

  private

  def clear_stale_polling_flags
    Source.where(polling: true).where("updated_at < ?", 10.minutes.ago).update_all(polling: false)
  end
end
