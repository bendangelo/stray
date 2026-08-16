class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.string :instance_name
      t.string :instance_domain
      t.string :smtp_host
      t.integer :smtp_port, default: 587
      t.string :smtp_username
      t.string :smtp_password
      t.string :ai_provider_name, default: "NONE"
      t.string :ai_provider_url
      t.string :ai_provider_api_key
      t.timestamps
    end

    Setting.create!(id: 1)
  end
end
