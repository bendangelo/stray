class CreateSources < ActiveRecord::Migration[8.1]
  def change
    create_table :sources do |t|
      t.references :user, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :url, null: false
      t.string :name
      t.string :icon_url
      t.string :external_id
      t.datetime :last_polled_at
      t.datetime :next_crawl_at
      t.integer :poll_interval, default: 1800
      t.boolean :active, default: true

      t.timestamps
    end
    add_index :sources, [:user_id, :external_id, :kind], unique: true
    add_index :sources, [:next_crawl_at, :active], where: "active = true"
  end
end
