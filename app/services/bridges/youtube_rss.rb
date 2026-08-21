require "feedjira"

module Bridges
    class YoutubeRss < Stray::Bridge
      BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"

      def self.matches?(url)
        uri = URI.parse(url)
        uri.host&.end_with?("youtube.com") && uri.path == "/feeds/videos.xml"
      rescue URI::InvalidURIError
        false
      end

      def self.handles_kind?(kind)
        kind == "youtube_channel"
      end

      def self.trust_level = :hidden_rss
      def self.site_homepage = "https://www.youtube.com"
      def self.last_tested_against = "2026-08"
      def self.author = "Stray"

      def extract(url)
        response = fetch(url)
        feed = Feedjira.parse(response.body)

        feed.entries.map do |entry|
          Stray::ExtractedContent.new(
            url: entry.url,
            title: entry.title,
            content_text: entry.content || entry.summary,
            content_html: nil,
            thumbnail_url: entry.media_thumbnail_url,
            published_at: entry.published,
            external_id: entry.entry_id.sub("yt:video:", ""),
            duration: nil,
            creator_identity: extract_creator(feed),
            tags: []
          )
        end
      end

      def extract_feed(url)
        extract(url)
      end

      def extract_backfill(url, limit:)
        channel_id = URI.parse(url).query.to_s[/channel_id=([^&]+)/, 1]
        return nil unless channel_id

        videos_url = "https://www.youtube.com/channel/#{channel_id}/videos"
        runner.channel_listings(videos_url, limit: limit).map do |data|
          Stray::ExtractedContent.new(
            url: data["url"] || "https://www.youtube.com/watch?v=#{data["id"]}",
            title: data["title"],
            content_text: nil,
            content_html: nil,
            thumbnail_url: extract_listing_thumbnail(data),
            published_at: Stray::YtDlp::UploadDate.parse(data["upload_date"]),
            external_id: data["id"],
            duration: data["duration"],
            creator_identity: extract_creator_from_data(data),
            tags: []
          )
        end
      rescue URI::InvalidURIError
        nil
      end

      private

      def runner
        @runner ||= Stray::YtDlp::Runner.new
      end

      def extract_listing_thumbnail(data)
        thumbnails = data["thumbnails"]
        first = thumbnails.is_a?(Array) ? thumbnails.first : nil
        first.is_a?(Hash) ? first["url"] : first || data["thumbnail"]
      end

      def extract_creator_from_data(data)
        return nil unless data["channel_id"] || data["channel"]

        Stray::CreatorIdentity.new(
          name: data["channel"],
          url: data["channel_url"],
          external_id: data["channel_id"],
          thumbnail_url: nil
        )
      end

      def fetch(url)
        response = http_client.get(url)
        raise Stray::ExtractionError, "youtube rss fetch failed: #{response.status}" unless response.status == 200

        response
      end

      def http_client
        Faraday.new do |conn|
          conn.headers["User-Agent"] = BROWSER_UA
          conn.headers["Accept-Language"] = "en"
          conn.headers["Cookie"] = "CONSENT=YES+cb"
          conn.response :follow_redirects
          conn.options.timeout = 30
          conn.options.open_timeout = 10
          conn.adapter :net_http
        end
      end

      def extract_creator(feed)
        Stray::CreatorIdentity.new(
          name: feed.title,
          url: feed.url,
          external_id: feed.youtube_channel_id,
          thumbnail_url: nil
        )
      end
    end
end
