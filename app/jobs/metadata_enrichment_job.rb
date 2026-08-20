class MetadataEnrichmentJob < ApplicationJob
  queue_as :default

  retry_on Stray::YtDlp::Error, wait: 1.minute, attempts: 2

  def perform(source_id, item_ids = nil)
    source = Source.find_by(id: source_id)
    return unless source
    return unless source.kind.in?(%w[video_channel youtube_channel])

    items = item_ids.presence ? Item.where(id: item_ids) : source.items.incomplete_metadata
    items = items.order(published_at: :desc, created_at: :desc).limit(50)

    items.each do |item|
      next unless item.incomplete_metadata?

      data = runner.single_video(item.url)
      updates = {}
      if item.duration.blank? && data["duration"].present?
        updates[:duration] = data["duration"]
      end
      if item.thumbnail_url.blank?
        thumbnail = data["thumbnail"] || data.dig("thumbnails", 0, "url")
        updates[:thumbnail_url] = thumbnail if thumbnail.present?
      end
      if item.published_at.blank?
        published_at = Stray::YtDlp::UploadDate.parse(data["upload_date"])
        updates[:published_at] = published_at if published_at
      end

      item.update!(updates) if updates.any?
      PoliteCrawl.sleep
    end
  end

  private

  def runner
    @runner ||= Stray::YtDlp::Runner.new
  end
end
