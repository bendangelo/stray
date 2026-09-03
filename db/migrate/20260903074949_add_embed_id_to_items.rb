class AddEmbedIdToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :embed_id, :string
  end
end
