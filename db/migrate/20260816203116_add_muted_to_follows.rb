class AddMutedToFollows < ActiveRecord::Migration[8.1]
  def change
    add_column :follows, :muted, :boolean, default: false, null: false
  end
end
