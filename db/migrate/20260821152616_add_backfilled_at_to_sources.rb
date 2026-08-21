class AddBackfilledAtToSources < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :backfilled_at, :datetime
  end
end
