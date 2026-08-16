# frozen_string_literal: true
class CreateCollections < ActiveRecord::Migration[8.1]
  def change
    create_table :collections do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :visibility, default: 0, null: false
      t.string :slug, null: false

      t.timestamps
    end
    add_index :collections, [ :user_id, :slug ], unique: true
  end
end
