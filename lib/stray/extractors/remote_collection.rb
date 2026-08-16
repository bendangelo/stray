require "faraday"
require "stray/url_guard"

module Stray
  module Extractors
    class RemoteCollection < Stray::Extractor
      MAX_ITEMS_PER_PAGE = 1000

      def self.matches?(url)
        url.to_s.end_with?("/manifest.json") || url.to_s.include?("/manifest.json?cursor=")
      end

      def self.handles_kind?(kind)
        kind == "stray_collection"
      end

      def extract(url)
        extract_feed(url).items
      end

      def extract_feed(url)
        raise Stray::UrlGuard::Blocked, "URL blocked by UrlGuard" unless Stray::UrlGuard.allowed?(url)

        response = http_client.get(url)
        raise "manifest fetch failed: #{response.status}" unless response.status == 200

        parse(response.body)
      end

      private

      def parse(body)
        data = JSON.parse(body)
        raise "not a stray-collection manifest" unless data["format"] == "stray-collection"

        items = (data["items"] || []).first(MAX_ITEMS_PER_PAGE).map do |item|
          ExtractedContent.new(
            url: item["url"],
            title: item["title"],
            content_text: item["content_text"],
            content_html: item["content_html"],
            thumbnail_url: item["thumbnail_url"],
            published_at: item["published_at"] && Time.parse(item["published_at"]),
            external_id: item["external_id"],
            duration: item["duration"],
            creator_identity: nil,
            tags: item["tags"] || []
          )
        end

        pagination = data["pagination"] || {}
        Stray::Extractor::FeedResult.new(
          items: items,
          next_cursor: pagination["next_cursor"],
          has_more: pagination["has_more"] || false
        )
      end

      def http_client
        Faraday.new do |conn|
          conn.response :follow_redirects, max: 3
          conn.options.timeout = 30
          conn.options.open_timeout = 10
          conn.adapter :net_http
        end
      end
    end
  end
end
