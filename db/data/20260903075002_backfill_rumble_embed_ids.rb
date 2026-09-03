# frozen_string_literal: true

class BackfillRumbleEmbedIds < ActiveRecord::Migration[8.1]
  def up
    Item.joins(:source).where(sources: { kind: :rumble_channel }).where(embed_id: nil).find_each do |item|
      embed_id = fetch_embed_id(item.url)
      item.update_column(:embed_id, embed_id) if embed_id
    rescue StandardError => e
      Rails.logger.warn("Rumble embed backfill failed for #{item.url}: #{e.message}")
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def fetch_embed_id(url)
    Stray::Bridges::Rumble.new.video_page(url)[:embed_id]
  end
end
