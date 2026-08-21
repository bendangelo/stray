class AddPublicationBufferMinutesToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :publication_buffer_minutes, :integer, default: 10, null: false
  end
end
