class AddPoliteCrawlDelayToSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :settings, :polite_crawl_delay, :float, default: 1.0
  end
end
