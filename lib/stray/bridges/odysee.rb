require "feedjira"
require "time"
require_relative "helpers"

module Stray
  module Bridges
    # Odysee channel feed via LBRY's per-channel RSS.
    # Feed URL: https://odysee.com/$/rss/@<handle>:<claimid>
    class Odysee
      HOSTS = %w[odysee.com].freeze
      BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"

      def self.matches?(url)
        uri = URI.parse(url)
        uri.host&.end_with?("odysee.com")
      rescue URI::InvalidURIError
        false
      end

      # Extract the @handle:id from a channel URL like https://odysee.com/@samtime:1
      def self.channel_handle(url)
        uri = URI.parse(url)
        match = uri.path.to_s.match(%r{^/@([^/]+)})
        match && match[1]
      rescue URI::InvalidURIError
        nil
      end

      def self.rss_url(url)
        handle = channel_handle(url)
        return nil unless handle

        "https://odysee.com/$/rss/@#{handle}"
      end

      # Fetch a channel's videos. Returns Array<Hash>.
      def channel_feed(url)
        rss = self.class.rss_url(url)
        raise Stray::ExtractionError, "Odysee: not a channel URL: #{url}" unless rss

        response = fetch(rss)
        feed = Feedjira.parse(response.body)
        channel_thumbnail = feed.itunes_image

        feed.entries.map do |entry|
          {
            url: entry.url,
            title: entry.title,
            external_id: entry.entry_id || entry.url,
            duration: parse_duration(entry),
            published_at: entry.published,
            thumbnail_url: entry.itunes_image || extract_thumbnail(entry),
            content_text: entry.summary || entry.content,
            content_html: entry.summary,
            tags: [],
            views: nil,
            live: nil,
            is_short: nil,
            creator_identity: {
              name: feed.title,
              url: url,
              external_id: self.class.channel_handle(url),
              thumbnail_url: channel_thumbnail
            }
          }
        end
      end

      # Odysee has no single-video page extraction here; single video URLs
      # fall through to generic_page. This raises for clarity.
      def video_page(url)
        raise Stray::ExtractionError, "Odysee: single video extraction not supported: #{url}"
      end

      private

      def parse_duration(entry)
        return nil unless entry.respond_to?(:itunes_duration)

        Helpers.dehumanize(entry.itunes_duration)
      end

      def extract_thumbnail(entry)
        content = entry.summary.to_s
        match = content.match(/<img src="([^"]+)"/)
        match && match[1]
      end

      def fetch(url)
        response = PoliteCrawl.get(url, http_client: http_client)
        raise Stray::ExtractionError, "Odysee fetch failed: #{response.status}" unless response.status == 200

        response
      end

      def http_client
        Faraday.new do |conn|
          conn.headers["User-Agent"] = BROWSER_UA
          conn.headers["Accept-Language"] = "en"
          conn.response :follow_redirects, max: 3
          conn.options.timeout = 30
          conn.options.open_timeout = 10
          conn.adapter :net_http
        end
      end
    end
  end
end
