require "json"
require "time"
require "faraday"
require "nokogiri"
require_relative "helpers"

module Stray
  module Extractors
    # Rumble channel feed + single video extraction.
    # Channel pages embed a <rum-videos-grid><script type="application/json"> blob
    # with the video list; video pages embed an ld+json VideoObject.
    class Rumble
      HOSTS = %w[rumble.com].freeze
      BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"

      def self.matches?(url)
        uri = URI.parse(url)
        uri.host&.end_with?("rumble.com")
      rescue URI::InvalidURIError
        false
      end

      def self.channel_slug(url)
        uri = URI.parse(url)
        match = uri.path.to_s.match(%r{^/(?:c|user)/([^/]+)})
        match && match[1]
      rescue URI::InvalidURIError
        nil
      end

      def self.video_id(url)
        uri = URI.parse(url)
        match = uri.path.to_s.match(%r{^/v([^/]+)})
        match && match[1]
      rescue URI::InvalidURIError
        nil
      end

      # Fetch a channel's videos. Returns Array<Hash>.
      def channel_feed(url)
        response = fetch(url)
        doc = Nokogiri::HTML(response.body)
        script = doc.at_css("rum-videos-grid script")
        raise Stray::ExtractionError, "Rumble: no rum-videos-grid data for #{url}" unless script

        data = JSON.parse(script.text)
        (data["items"] || []).map { |item| video_hash(item) }
      end

      # Fetch a single video page. Returns Hash (some fields may be nil).
      def video_page(url)
        response = fetch(url)
        doc = Nokogiri::HTML(response.body)
        ld = extract_video_object(doc)
        return video_hash(ld) if ld

        # Fallback to OG meta if no ld+json VideoObject.
        {
          url: url,
          title: Helpers.find_title(doc),
          external_id: self.class.video_id(url),
          duration: Helpers.find_duration(doc),
          published_at: Helpers.find_publish_date(doc),
          thumbnail_url: Helpers.find_thumbnail(doc),
          content_text: Helpers.find_description(doc),
          content_html: nil,
          tags: [],
          views: nil,
          live: nil,
          is_short: nil,
          creator_identity: nil
        }
      end

      private

      def video_hash(item)
        by = item["by"] || {}
        {
          url: item["url"],
          title: item["title"],
          external_id: item["id"].to_s,
          duration: item["duration"],
          published_at: parse_time(item["upload_date"]),
          thumbnail_url: item["thumb"],
          content_text: nil,
          content_html: nil,
          tags: Array(item["tags"]).first(5),
          views: item["views"],
          live: item["live"],
          is_short: item["is_short"],
          creator_identity: {
            name: by["name"],
            url: by["url"],
            external_id: by["eid"],
            thumbnail_url: by["thumb"]
          }
        }
      end

      def extract_video_object(doc)
        script = doc.at('script[type="application/ld+json"]')
        return nil unless script

        data = JSON.parse(script.text)
        entries = data.is_a?(Array) ? data : [ data ]
        entries.find { |e| e["@type"] == "VideoObject" }
      rescue JSON::ParserError
        nil
      end

      def parse_time(value)
        return nil if value.nil? || value.empty?

        Time.iso8601(value)
      rescue ArgumentError
        nil
      end

      def fetch(url)
        response = http_client.get(url)
        raise Stray::ExtractionError, "Rumble fetch failed: #{response.status}" unless response.status == 200

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
