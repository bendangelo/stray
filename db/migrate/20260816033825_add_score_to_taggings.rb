class AddScoreToTaggings < ActiveRecord::Migration[8.1]
  def change
    add_column :taggings, :score, :float
  end
end
