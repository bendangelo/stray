# frozen_string_literal: true
class CreateRemoteCollections < ActiveRecord::Migration[8.1]
  def change
    create_table :remote_collections do |t|
      t.references :source, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.string :manifest_url, null: false
      t.string :producer_instance_name
      t.string :collection_name
      t.string :last_cursor
      t.datetime :last_synced_at
      t.string :last_error
      t.datetime :last_error_at
      t.integer :item_count, default: 0

      t.timestamps
    end
    add_index :remote_collections, :source_id, unique: true
    add_index :remote_collections, [ :user_id, :manifest_url ], unique: true
  end
end
