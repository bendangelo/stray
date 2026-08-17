class AddStatusToSources < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :status, :integer, null: false, default: 0
    add_index :sources, :status
  end
end
