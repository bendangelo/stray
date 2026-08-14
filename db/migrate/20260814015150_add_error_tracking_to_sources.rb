class AddErrorTrackingToSources < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :last_error, :string
    add_column :sources, :last_error_at, :datetime
  end
end
