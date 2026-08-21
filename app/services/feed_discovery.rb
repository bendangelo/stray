require "nokogiri"

class FeedDiscovery
  FEED_TYPES = %w[application/rss+xml application/atom+xml].freeze

  class << self
    def find_feed_url(html, base_url)
      doc = Nokogiri::HTML(html)
      links = doc.css('link[rel="alternate"]').select { |l| FEED_TYPES.include?(l["type"]) }
      return nil if links.empty?

      rss_link = links.find { |l| l["type"] == "application/rss+xml" } || links.first
      href = rss_link["href"]
      return nil unless href

      absolute_url(href, base_url)
    end

    private

    def absolute_url(href, base_url)
      URI.join(base_url, href).to_s
    rescue URI::InvalidURIError
      href
    end
  end
end
