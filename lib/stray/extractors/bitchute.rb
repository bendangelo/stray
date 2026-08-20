require "faraday"
require "nokogiri"
require_relative "helpers"

module Stray
  module Extractors
    # Bitchute channel feed + single video extraction.
    # Ported from stray_video's BitchuteSpider.
    class Bitchute
      HOSTS = %w[bitchute.com].freeze
      BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"

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

      # Fetch a channel's videos. Returns Array<Hash>.
      def channel_feed(url)
        response = fetch(url)
        doc = Nokogiri::HTML(response.body)
        cards = doc.css(".channel-videos-container")

        cards.map do |card|
          title = card.at(".channel-videos-title a")&.text
          next if title.nil? || title.empty?

          thumbnail_url = card.at_css(".channel-videos-image img")&.[]("data-src")
          eid, channel_eid = video_and_channel_eid(thumbnail_url)

          {
            url: "https://www.bitchute.com/video/#{eid}",
            title: title,
            external_id: eid,
            duration: Helpers.dehumanize(card.at(".video-duration")&.text),
            published_at: Helpers.dehumanize_time(card.at_css(".channel-videos-details")&.text),
            thumbnail_url: thumbnail_url,
            content_text: card.at_css(".channel-videos-text")&.text,
            content_html: nil,
            tags: [],
            views: Helpers.dehumanize(card.at_css(".video-views")&.text),
            live: nil,
            is_short: nil,
            creator_identity: {
              name: nil,
              url: "https://www.bitchute.com/channel/#{channel_eid}",
              external_id: channel_eid,
              thumbnail_url: nil
            }
          }
        end.compact
      end

      # Fetch a single video page. Returns Hash.
      def video_page(url)
        response = fetch(url)
        doc = Nokogiri::HTML(response.body)
        return nil unless doc.at("#video-title")

        thumbnail_url = Helpers.find_meta(doc, "og:image")
        eid, channel_eid = video_and_channel_eid(thumbnail_url)

        {
          url: url,
          title: doc.at("#video-title").text,
          external_id: eid,
          duration: Helpers.dehumanize(Helpers.find_meta(doc, "duration")),
          published_at: Helpers.dehumanize_time(doc.at(".video-publish-date")&.text.to_s.split("at")[1]),
          thumbnail_url: thumbnail_url,
          content_text: doc.at("#video-description .full")&.text,
          content_html: nil,
          tags: doc.css(".tags a").map { |i| i.text[1..-1] }.first(5),
          views: nil,
          live: nil,
          is_short: nil,
          creator_identity: {
            name: doc.at(".channel-banner p")&.text,
            url: "https://www.bitchute.com/channel/#{channel_eid}",
            external_id: channel_eid,
            thumbnail_url: doc.at(".channel-banner img")&.[]("data-src")
          }
        }
      end

      private

      def video_and_channel_eid(thumbnail_url)
        return [ nil, nil ] if thumbnail_url.nil?

        matches = thumbnail_url.match(%r{images/(.+)/(.+)_})
        matches ? [ matches[2], matches[1] ] : [ nil, nil ]
      end

      def fetch(url)
        response = http_client.get(url)
        raise Stray::ExtractionError, "Bitchute fetch failed: #{response.status}" unless response.status == 200

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
