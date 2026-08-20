require "digest"
require "faraday"
require "readability"

module Extractors
  class GenericPage < Extractor
      def self.matches?(url)
        uri = URI.parse(url)
        uri.scheme.in?(%w[http https]) && uri.host.present?
      rescue URI::InvalidURIError
        false
      end

      def self.handles_kind?(kind)
        kind == "generic_page"
      end

      def extract(url)
        response = fetch(url)
        doc = Readability::Document.new(response.body)
        content_html = doc.content
        text = extract_text(content_html)

        ExtractedContent.new(
          url: url,
          title: extract_title(response.body, doc.title),
          content_text: text,
          content_html: content_html,
          thumbnail_url: extract_thumbnail(response.body),
          published_at: extract_published_at(response.body),
          external_id: Digest::SHA256.hexdigest(url)[0, 32],
          duration: nil,
          creator_identity: extract_creator(response.body, url),
          tags: []
        )
      end

      def extract_feed(url)
        [ extract(url) ]
      end

      private

      def fetch(url)
        raise UrlGuard::Blocked, "URL blocked by UrlGuard" unless UrlGuard.allowed?(url)

        response = http_client.get(url)
        raise Stray::ExtractionError, "page fetch failed: #{response.status}" unless response.status == 200

        response
      end

      def http_client
        Faraday.new do |conn|
          conn.response :follow_redirects, max: 3
          conn.options.timeout = 30
          conn.options.open_timeout = 10
          conn.adapter :net_http
        end
      end

      def extract_text(html)
        Nokogiri::HTML(html).text.to_s.strip
      end

      def extract_title(body, readability_title)
        meta = Nokogiri::HTML(body).at_xpath('//meta[@property="og:title"]')&.attr("content")
        meta.presence || readability_title
      end

      def extract_thumbnail(body)
        Nokogiri::HTML(body).at_xpath('//meta[@property="og:image"]')&.attr("content")
      end

      def extract_published_at(body)
        doc = Nokogiri::HTML(body)
        meta = doc.at_xpath('//meta[@property="article:published_time"]') ||
               doc.at_xpath('//meta[@name="article:published_time"]') ||
               doc.at_xpath('//meta[@name="date"]')
        return nil unless meta

        value = meta.attr("content")
        Time.parse(value)
      rescue ArgumentError
        nil
      end

      def extract_creator(body, url)
        uri = URI.parse(url)
        CreatorIdentity.new(
          name: uri.host,
          url: "#{uri.scheme}://#{uri.host}",
          external_id: uri.host,
          thumbnail_url: nil
        )
      rescue URI::InvalidURIError
        nil
      end
    end
end
