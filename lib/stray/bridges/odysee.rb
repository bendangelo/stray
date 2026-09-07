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
        feed_from_rss(response.body, url)
      end

      # Parse a pre-fetched RSS body into Array<Hash>.
      def feed_from_rss(body, url)
        feed = Feedjira.parse(body)
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

    # Fetch a single video page. Returns Hash.
    def video_page(url)
      data = runner.single_video(url)

      channel_handle = extract_channel_handle(data, url)
      channel_url = "https://odysee.com/@#{channel_handle}" if channel_handle

      {
        url: data["url"] || url,
        title: data["title"],
        external_id: data["id"],
        duration: data["duration"],
        published_at: parse_time(data["upload_date"]),
        thumbnail_url: extract_thumbnail(data),
        content_text: data["description"],
        content_html: nil,
        tags: extract_tags(data),
        views: nil,
        live: nil,
        is_short: nil,
        creator_identity: {
          name: data["channel"],
          url: channel_url,
          external_id: channel_handle,
          thumbnail_url: nil
        }
      }
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

    def extract_channel_handle(data, url)
      data["channel_id"] || data["channel"] ||
        URI.parse(url).path.to_s.match(%r{^/@([^/]+:[^/]+)/})&.to_a&.last
    rescue URI::InvalidURIError
      nil
    end

    def extract_thumbnail(data)
      thumbnails = data["thumbnails"]
      first = thumbnails.is_a?(Array) ? thumbnails.first : nil
      first.is_a?(Hash) ? first["url"] : first || data["thumbnail"]
    end

    def extract_tags(data)
      cats = Array(data["categories"])
      tags = Array(data["tags"])
      (cats + tags).map { |t| t.to_s.downcase.strip }.reject(&:empty?).uniq.first(5)
    end

    def parse_time(value)
      return nil if value.nil? || value.empty?

      Time.strptime(value, "%Y%m%d")
    rescue ArgumentError
      nil
    end

    def runner
      @runner ||= Stray::YtDlp::Runner.new
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
