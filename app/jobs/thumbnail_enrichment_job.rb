class ThumbnailEnrichmentJob < ApplicationJob
  queue_as :default

  retry_on Stray::YtDlp::Error, wait: 1.minute, attempts: 2

  def perform(source_id, item_ids = nil)
    source = Source.find_by(id: source_id)
    return unless source

    items = item_ids.presence ? Item.where(id: item_ids) : source.items.where(thumbnail_url: nil)
    items = items.order(published_at: :desc).limit(50)

    items.each do |item|
      next if item.thumbnail_url.present?

      data = runner.single_video(item.url)
      thumbnail = data["thumbnail"] || data.dig("thumbnails", 0, "url")
      item.update!(thumbnail_url: thumbnail) if thumbnail.present?
    end
  end

  private

  def runner
    @runner ||= Stray::YtDlp::Runner.new
  end
end
