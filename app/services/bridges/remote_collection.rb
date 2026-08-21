require "faraday"

module Bridges
  class RemoteCollection < Stray::Bridge
      MAX_ITEMS_PER_PAGE = 1000

      def self.matches?(url)
        url.to_s.end_with?("/manifest.json") || url.to_s.include?("/manifest.json?cursor=")
      end

      def self.manifest_url_for(url)
        return url if matches?(url)

        uri = URI.parse(url)
        return nil unless uri.host
        return nil unless uri.path =~ %r{^/c/([A-Za-z0-9]{24})$}

        "#{uri.scheme}://#{uri.host}/c/#{$1}/manifest.json"
      rescue URI::InvalidURIError
        nil
      end

      def self.handles_kind?(kind)
        kind == "stray_collection"
      end

      def extract(url)
        extract_feed(url).items
      end

      def extract_feed(url)
        raise UrlGuard::Blocked, "URL blocked by UrlGuard" unless UrlGuard.allowed?(url)

        response = http_client.get(url)
        raise "manifest fetch failed: #{response.status}" unless response.status == 200

        parse(response.body)
      end

      private

      def parse(body)
        data = JSON.parse(body)
        raise "not a stray-collection manifest" unless data["format"] == "stray-collection"

        items = (data["items"] || []).first(MAX_ITEMS_PER_PAGE).map do |item|
          Stray::ExtractedContent.new(
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
        Stray::Bridge::FeedResult.new(
          items: items,
          next_cursor: pagination["next_cursor"],
          has_more: pagination["has_more"] || false,
          collection_name: data.dig("collection", "name"),
          producer_instance_name: data.dig("producer", "instance_name")
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
