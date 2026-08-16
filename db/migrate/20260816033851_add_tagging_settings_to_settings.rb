class AddTaggingSettingsToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :zero_shot_threshold, :float, default: 0.35
    add_column :settings, :zero_shot_top_n, :integer, default: 5
    add_column :settings, :llm_tagging_enabled, :boolean, default: false
    add_column :settings, :llm_tagging_model, :string, default: "qwen2.5:1.5b"
    add_column :settings, :embedding_model, :string
    add_column :settings, :embedding_model_present, :boolean, default: false
  end
end
