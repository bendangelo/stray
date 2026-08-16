# frozen_string_literal: true
class CreateCollectionMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :collection_memberships do |t|
      t.references :collection, null: false, foreign_key: true
      t.references :source, null: false, foreign_key: true

      t.timestamps
    end
    add_index :collection_memberships, [ :collection_id, :source_id ], unique: true
  end
end
