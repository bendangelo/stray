require "feedjira"

module Stray
  module Extractors
    class RssAtom < Stray::Extractor
      def self.matches?(url)
        uri = URI.parse(url)
        path = uri.path.downcase
        path.end_with?(".xml", ".rss", ".atom") ||
          path.include?("/feed") ||
          path.include?("/rss") ||
          path.include?("/atom") ||
          path.include?("/feeds/")
      rescue URI::InvalidURIError
        false
      end

      def self.handles_kind?(kind)
        kind == "rss_feed"
      end

      def extract(url)
        response = http_client.get(url)
        feed = Feedjira.parse(response.body)

        feed.entries.map do |entry|
          ExtractedContent.new(
            url: entry.url,
            title: entry.title,
            content_text: entry.content || entry.summary,
            content_html: entry.content,
            thumbnail_url: extract_thumbnail(entry),
            published_at: entry.published,
            external_id: entry.entry_id || entry.url,
            duration: nil,
            creator_identity: extract_creator(feed),
            tags: []
          )
        end
      end

      def extract_feed(url)
        extract(url)
      end

      private

      def http_client
        Faraday.new do |conn|
          conn.response :follow_redirects
          conn.adapter :net_http
        end
      end

      def extract_thumbnail(entry)
        entry.respond_to?(:media_thumbnail_url) ? entry.media_thumbnail_url : nil
      end

      def extract_creator(feed)
        return nil unless feed.respond_to?(:title) || feed.respond_to?(:url)

        CreatorIdentity.new(
          name: feed.title,
          url: feed.url,
          external_id: feed.feed_url || feed.url,
          thumbnail_url: nil
        )
      end
    end
  end
end
