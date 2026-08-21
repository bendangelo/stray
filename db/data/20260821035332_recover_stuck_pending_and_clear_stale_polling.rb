# frozen_string_literal: true

class RecoverStuckPendingAndClearStalePolling < ActiveRecord::Migration[8.1]
  def up
    # Clear stale polling flags (same as the sweep does, one-off for current state)
    Source.where(polling: true).where("updated_at < ?", 10.minutes.ago).update_all(polling: false)

    # Recover abandoned pending sources into recovering so the sweep retries them
    # with backoff instead of leaving them stuck in "Resolving…".
    Source.where(status: :pending)
      .where(polling: false)
      .where("last_polled_at IS NULL")
      .where("next_crawl_at IS NULL")
      .where("created_at < ?", 10.minutes.ago)
      .find_each do |source|
        source.update!(
          status: :recovering,
          last_error: "Recovered by data migration — stuck in pending.",
          last_error_at: Time.current,
          recovery_attempts: 1,
          next_crawl_at: 2.minutes.from_now
        )
      end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
