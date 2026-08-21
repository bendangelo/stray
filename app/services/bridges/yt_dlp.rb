module Bridges
  class YtDlp < Stray::Bridge
      VIDEO_HOSTS = %w[bitchute.com].freeze

      def self.matches?(url)
        uri = URI.parse(url)
        VIDEO_HOSTS.any? { |host| uri.host&.end_with?(host) }
      rescue URI::InvalidURIError
        false
      end

      def self.handles_kind?(kind)
        kind == "video_channel"
      end

      def extract(url)
        data = runner.single_video(url)

        Stray::ExtractedContent.new(
          url: canonicalize_url(url, data),
          title: data["title"],
          content_text: data["description"],
          content_html: nil,
          thumbnail_url: data["thumbnail"],
          published_at: Stray::YtDlp::UploadDate.parse(data["upload_date"]),
          external_id: data["id"],
          duration: data["duration"],
          creator_identity: extract_creator(data),
          tags: extract_tags(data)
        )
      end

      def extract_channel(url)
        entries = runner.channel_listings(url)

        entries.map do |data|
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

      def extract_feed(url)
        extract_channel(url)
      end

      private

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

      def runner
        @runner ||= Stray::YtDlp::Runner.new
      end

      def extract_listing_thumbnail(data)
        thumbnails = data["thumbnails"]
        first = thumbnails.is_a?(Array) ? thumbnails.first : nil
        first.is_a?(Hash) ? first["url"] : first ||
          data["thumbnail"]
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

      def extract_tags(data)
        cats = Array(data["categories"])
        tags = Array(data["tags"])
        combined = (cats + tags).map { |t| t.to_s.downcase.strip }.reject(&:empty?).uniq
        combined.first(5)
      end
    end
end
