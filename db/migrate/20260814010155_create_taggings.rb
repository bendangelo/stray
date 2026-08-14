class CreateTaggings < ActiveRecord::Migration[8.1]
  def change
    create_table :taggings do |t|
      t.references :item, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.integer :source, null: false, default: 0

      t.timestamps
    end
    add_index :taggings, [:item_id, :tag_id, :source], unique: true
  end
end
