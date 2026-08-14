class CreateItems < ActiveRecord::Migration[8.1]
  def change
    create_table :items do |t|
      t.references :source, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :title, null: false
      t.string :url, null: false
      t.text :content_text
      t.text :content_html
      t.text :summary
      t.string :thumbnail_url
      t.integer :duration
      t.datetime :published_at
      t.datetime :fetched_at
      t.binary :embedding
      t.integer :state, default: 0

      t.timestamps
    end
    add_index :items, [:source_id, :external_id], unique: true
    add_index :items, [:user_id, :state, :published_at]
  end
end
