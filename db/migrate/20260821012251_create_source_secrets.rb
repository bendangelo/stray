class CreateSourceSecrets < ActiveRecord::Migration[8.1]
  def change
    create_table :source_secrets do |t|
      t.references :source, null: false, foreign_key: true
      t.string :field_name, null: false
      t.text :value
      t.timestamps
    end
    add_index :source_secrets, [ :source_id, :field_name ], unique: true
  end
end
