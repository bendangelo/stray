# frozen_string_literal: true

class RewritePeertubeSourceUrlsToApi < ActiveRecord::Migration[8.1]
  def up
    Source.where(kind: :peertube_channel).find_each do |source|
      api_url = Stray::Bridges::Peertube.api_url_for(source.url)
      next unless api_url && api_url != source.url

      source.update_columns(
        url: api_url,
        channel_url: source.channel_url || source.url,
        etag: nil,
        last_modified: nil
      )
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
