# frozen_string_literal: true

class BackfillStuckPendingSources < ActiveRecord::Migration[8.1]
  def up
    Source.where(status: :pending)
      .where(last_polled_at: nil)
      .where("created_at < ?", 10.minutes.ago)
      .find_each do |source|
        source.update!(
          status: :failed,
          last_error: "Stuck in pending — no successful poll. Backfilled by data migration.",
          last_error_at: Time.current
        )
      end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
