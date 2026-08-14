require "time"

module Stray
  module Extractors
    class YtDlp < Stray::Extractor
      def self.matches?(url)
        uri = URI.parse(url)
        return false if uri.host&.end_with?("youtube.com") && uri.path == "/feeds/videos.xml"

        true
      rescue URI::InvalidURIError
        false
      end

      def extract(url)
        data = runner.single_video(url)

        ExtractedContent.new(
          title: data["title"],
          content_text: data["description"],
          content_html: nil,
          thumbnail_url: data["thumbnail"],
          published_at: parse_upload_date(data["upload_date"]),
          external_id: data["id"],
          duration: data["duration"],
          creator_identity: extract_creator(data)
        )
      end

      def extract_channel(url)
        entries = runner.channel_listings(url)

        entries.map do |data|
          ExtractedContent.new(
            title: data["title"],
            content_text: nil,
            content_html: nil,
            thumbnail_url: data.dig("thumbnails", 0, "url"),
            published_at: parse_upload_date(data["upload_date"]),
            external_id: data["id"],
            duration: data["duration"],
            creator_identity: extract_creator(data)
          )
        end
      end

      private

      def runner
        @runner ||= Stray::YtDlp::Runner.new
      end

      def extract_creator(data)
        return nil unless data["channel_id"] || data["channel"]

        CreatorIdentity.new(
          name: data["channel"],
          url: data["channel_url"],
          external_id: data["channel_id"],
          thumbnail_url: nil
        )
      end

      def parse_upload_date(date_str)
        return nil unless date_str

        Time.strptime(date_str, "%Y%m%d").utc
      end
    end
  end
end
