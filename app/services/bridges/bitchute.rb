module Bridges
  class Bitchute < Stray::Bridge
    include HashMapper

    def self.matches?(url)
      Stray::Bridges::Bitchute.matches?(url)
    end

    def self.handles_kind?(kind)
      kind == "bitchute_channel"
    end

    def self.trust_level = :scraped_html
    def self.site_homepage = "https://www.bitchute.com"
    def self.last_tested_against = "2026-08"
    def self.author = "Stray"

    def extract(url)
      map(Stray::Bridges::Bitchute.new.video_page(url))
    end

    def extract_feed(url)
      Stray::Bridges::Bitchute.new.channel_feed(url).map { |h| map(h) }
    end

    def extract_backfill(url, limit:)
      runner.channel_listings(url, limit: limit).map do |data|
        Stray::ExtractedContent.new(
          url: canonicalize_url(data["url"], data),
          title: data["title"],
          content_text: nil,
          content_html: nil,
          thumbnail_url: extract_listing_thumbnail(data),
          published_at: Stray::YtDlp::UploadDate.parse(data["upload_date"]),
          external_id: data["id"],
          duration: data["duration"],
          creator_identity: extract_creator(data),
          tags: []
        )
      end
    end

    private

    def runner
      @runner ||= Stray::YtDlp::Runner.new
    end

    def canonicalize_url(url, data)
      candidate = data["url"] || data["webpage_url"] || url
      parsed = URI.parse(candidate)
      if parsed.host&.include?("bitchute.com") && data["id"]
        "https://www.bitchute.com/video/#{data["id"]}"
      else
        candidate
      end
    rescue URI::InvalidURIError
      candidate
    end

    def extract_listing_thumbnail(data)
      thumbnails = data["thumbnails"]
      first = thumbnails.is_a?(Array) ? thumbnails.first : nil
      first.is_a?(Hash) ? first["url"] : first || data["thumbnail"]
    end

    def extract_creator(data)
      return nil unless data["channel_id"] || data["channel"]

      Stray::CreatorIdentity.new(
        name: data["channel"],
        url: data["channel_url"],
        external_id: data["channel_id"],
        thumbnail_url: nil
      )
    end
  end
end
