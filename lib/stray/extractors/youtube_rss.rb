require "feedjira"

module Stray
  module Extractors
    class YoutubeRss < Stray::Extractor
      def self.matches?(url)
        uri = URI.parse(url)
        uri.host&.end_with?("youtube.com") && uri.path == "/feeds/videos.xml"
      rescue URI::InvalidURIError
        false
      end

      def extract(url)
        response = http_client.get(url)
        feed = Feedjira.parse(response.body)

        feed.entries.map do |entry|
          ExtractedContent.new(
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

      private

      def http_client
        Faraday.new do |conn|
          conn.response :follow_redirects
          conn.adapter :net_http
        end
      end

      def extract_creator(feed)
        CreatorIdentity.new(
          name: feed.title,
          url: feed.url,
          external_id: feed.youtube_channel_id,
          thumbnail_url: nil
        )
      end
    end
  end
end
