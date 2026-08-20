class AddChannelUrlToSources < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :channel_url, :string
  end
end
