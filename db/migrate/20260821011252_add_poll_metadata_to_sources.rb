class AddPollMetadataToSources < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :etag, :string
    add_column :sources, :last_modified, :string
    add_column :sources, :consecutive_empty_polls, :integer, null: false, default: 0
  end
end
