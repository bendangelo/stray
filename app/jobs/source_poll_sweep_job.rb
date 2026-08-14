class SourcePollSweepJob < ApplicationJob
  queue_as :default

  def perform
    Source.due_for_poll.in_batches(of: 100) do |batch|
      batch.each do |source|
        SourcePollJob.perform_later(source.id)
      end
    end
  end
end
