# frozen_string_literal: true

class RewriteOdyseeSourceUrlsToRss < ActiveRecord::Migration[8.1]
  def up
    Source.where(kind: :odysee_channel).find_each do |source|
      channel_url = source.channel_url.presence || source.url
      rss_url = Stray::Bridges::Odysee.rss_url(channel_url)
      next unless rss_url && rss_url != source.url

      source.update_columns(
        url: rss_url,
        channel_url: channel_url,
        etag: nil,
        last_modified: nil
      )
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
