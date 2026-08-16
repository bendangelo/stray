class CreateInteractions < ActiveRecord::Migration[8.1]
  def change
    create_table :interactions do |t|
      t.references :item, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :kind, null: false
      t.datetime :created_at, null: false
      t.index [:item_id, :user_id, :kind], unique: true, name: "index_interactions_on_item_user_kind_unique"
      t.index [:user_id, :created_at]
    end
  end
end
