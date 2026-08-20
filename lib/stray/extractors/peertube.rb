require "json"
require "time"
require "faraday"
require_relative "helpers"

module Stray
  module Extractors
    # Peertube channel feed via the instance's REST API.
    # Host-agnostic: works for any Peertube instance.
    # API: GET /api/v1/video-channels/<handle>/videos?count=100
    class Peertube
      BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"

      def self.matches?(url)
        uri = URI.parse(url)
        uri.host.present? && uri.path.to_s.match?(%r{/video-channels/|/c/})
      rescue URI::InvalidURIError
        false
      end

      # Extract the channel handle from a URL like https://host/video-channels/fedi
      # or https://host/c/fedi
      def self.channel_handle(url)
        uri = URI.parse(url)
        match = uri.path.to_s.match(%r{/(?:video-channels|c)/([^/]+)})
        match && match[1]
      rescue URI::InvalidURIError
        nil
      end

      # Fetch a channel's videos. Returns Array<Hash>.
      def channel_feed(url)
        handle = self.class.channel_handle(url)
        raise Stray::ExtractionError, "Peertube: not a channel URL: #{url}" unless handle

        uri = URI.parse(url)
        api_url = "#{uri.scheme}://#{uri.host}/api/v1/video-channels/#{handle}/videos?count=100"
        response = fetch(api_url)
        data = JSON.parse(response.body)

        (data["data"] || []).map { |v| video_hash(v, uri) }
      end

      # Fetch a single video. Returns Hash.
      def video_page(url)
        uri = URI.parse(url)
        uuid = uri.path.to_s.match(%r{/w/([^/]+)})&.[](1)
        raise Stray::ExtractionError, "Peertube: not a video URL: #{url}" unless uuid

        api_url = "#{uri.scheme}://#{uri.host}/api/v1/videos/#{uuid}"
        response = fetch(api_url)
        video_hash(JSON.parse(response.body), uri)
      end

      # Fetch just the tags for a single video by its UUID.
      # The channel-listing API omits tags; only the single-video endpoint returns them.
      def fetch_tags(host, uuid)
        response = fetch("https://#{host}/api/v1/videos/#{uuid}")
        Array(JSON.parse(response.body)["tags"]).first(5)
      end

      private

      def video_hash(v, uri)
        channel = v["channel"] || {}
        {
          url: v["url"] || "#{uri.scheme}://#{uri.host}/w/#{v["uuid"]}",
          title: v["name"],
          external_id: v["uuid"] || v["id"].to_s,
          duration: v["duration"],
          published_at: parse_time(v["publishedAt"]),
          thumbnail_url: absolute(uri, v["thumbnailPath"]),
          content_text: v["description"] || v["truncatedDescription"],
          content_html: nil,
          tags: Array(v["tags"]).first(5),
          views: v["views"],
          live: v["isLive"],
          is_short: nil,
          creator_identity: {
            name: channel["displayName"] || channel["name"],
            url: channel["url"],
            external_id: channel["name"],
            thumbnail_url: absolute(uri, channel.dig("avatar", "path"))
          }
        }
      end

      def absolute(uri, path)
        return nil if path.nil? || path.empty?
        return path if path.start_with?("http")

        "#{uri.scheme}://#{uri.host}#{path}"
      end

      def parse_time(value)
        return nil if value.nil? || value.empty?

        Time.iso8601(value)
      rescue ArgumentError
        nil
      end

      def fetch(url)
        response = PoliteCrawl.get(url, http_client: http_client)
        raise Stray::ExtractionError, "Peertube fetch failed: #{response.status}" unless response.status == 200

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
