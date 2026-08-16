class AddPollingToSources < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :polling, :boolean, default: false, null: false
  end
end
