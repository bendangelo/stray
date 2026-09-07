require "faraday"
require "json"
require "uri"
require_relative "helpers"

module Stray
  module Bridges
    # Bitchute channel feed + single video extraction.
    # Channel listings come from the JSON API — channel pages are a JS SPA, not scrapable.
    class Bitchute
      HOSTS = %w[bitchute.com].freeze
      BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"
      API_BASE = "https://api.bitchute.com"
      CHANNEL_VIDEOS_PATH = "/api/beta/channel/videos"
      VIDEO_PATH = "/api/beta/video"
      PAGE_MIN = 10
      PAGE_MAX = 50

      def self.matches?(url)
        uri = URI.parse(url)
        uri.host&.end_with?("bitchute.com")
      rescue URI::InvalidURIError
        false
      end

      def self.channel_id(url)
        uri = URI.parse(url)
        match = uri.path.to_s.match(%r{^/channel/([^/]+)})
        match && match[1]
      rescue URI::InvalidURIError
        nil
      end

      def self.video_id(url)
        uri = URI.parse(url)
        match = uri.path.to_s.match(%r{^/video/([^/]+)})
        match && match[1]
      rescue URI::InvalidURIError
        nil
      end

      # Fetch a channel's latest videos from the JSON API. Returns Array<Hash>.
      def channel_feed(url, limit: PAGE_MAX)
        channel_id = self.class.channel_id(url)
        return [] if channel_id.nil?

        items = []
        offset = 0
        loop do
          page = fetch_channel_videos(channel_id, offset: offset)
          break if page.empty?

          items.concat(page)
          break if items.size >= limit
          break if page.size < PAGE_MAX

          offset += page.size
        end

        items.first(limit)
      end

      # Fetch one API page (PAGE_MAX) of a channel's videos. Returns Array<Hash>.
      def fetch_channel_videos(channel_id, offset:)
        data = api_post(CHANNEL_VIDEOS_PATH, channel_id: channel_id, limit: PAGE_MAX, offset: offset, order_by: "latest")
        Array(data["videos"]).map { |video| normalize_video(video, channel_id) }
      end

      # Fetch a single video from the JSON API. Returns Hash.
      def video_page(url)
        video_id = self.class.video_id(url)
        return nil if video_id.nil?

        data = api_post(VIDEO_PATH, video_id: video_id)
        normalize_detail(data)
      end

      private

      def normalize_video(video, channel_id)
        {
          url: "https://www.bitchute.com#{video["video_url"]}",
          title: video["video_name"],
          external_id: video["video_id"],
          duration: Helpers.dehumanize(video["duration"]),
          published_at: parse_iso8601(video["date_published"]),
          thumbnail_url: video["thumbnail_url"],
          content_text: video["description"],
          content_html: nil,
          tags: [],
          views: video["view_count"],
          live: nil,
          is_short: nil,
          creator_identity: {
            name: nil,
            url: "https://www.bitchute.com/channel/#{channel_id}",
            external_id: channel_id,
            thumbnail_url: nil
          }
        }
      end

      def normalize_detail(data)
        channel = data["channel"] || {}
        channel_id = channel["channel_id"]

        {
          url: "https://www.bitchute.com/video/#{data["video_id"]}/",
          title: data["video_name"],
          external_id: data["video_id"],
          duration: Helpers.dehumanize(data["duration"]),
          published_at: parse_iso8601(data["date_published"]),
          thumbnail_url: data["thumbnail_url"],
          content_text: data["description"],
          content_html: nil,
          tags: Array(data["hashtags"]),
          views: data["view_count"],
          live: nil,
          is_short: nil,
          creator_identity: {
            name: channel["channel_name"],
            url: channel_id ? "https://www.bitchute.com/channel/#{channel_id}" : nil,
            external_id: channel_id,
            thumbnail_url: channel["thumbnail_url"]
          }
        }
      end

      def parse_iso8601(value)
        return nil if value.to_s.strip.empty?

        Time.parse(value)
      rescue ArgumentError
        nil
      end

      def api_post(path, payload)
        response = PoliteCrawl.post(
          "#{API_BASE}#{path}",
          http_client: http_client,
          json: payload
        )
        raise Stray::ExtractionError, "Bitchute API failed: #{response.status}" unless response.status == 200

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Stray::ExtractionError, "Bitchute API returned invalid JSON: #{e.message}"
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
