class AddBackfillLimitToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :backfill_limit, :integer
  end
end
