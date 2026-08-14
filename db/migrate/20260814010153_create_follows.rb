class CreateFollows < ActiveRecord::Migration[8.1]
  def change
    create_table :follows do |t|
      t.references :user, null: false, foreign_key: true
      t.references :source, null: false, foreign_key: true
      t.float :weight, default: 1.0

      t.timestamps
    end
    add_index :follows, [:user_id, :source_id], unique: true
  end
end
