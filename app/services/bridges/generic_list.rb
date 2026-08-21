require "digest"
require "faraday"
require "nokogiri"

module Bridges
  class GenericList < Stray::Bridge
    MIN_ITEMS = 3

    def self.matches?(url)
      uri = URI.parse(url)
      uri.scheme.in?(%w[http https]) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    def self.handles_kind?(kind)
      kind == "generic_list"
    end

    def self.detect(html_or_url)
      bridge = new
      html = bridge.send(:fetch_html, html_or_url)
      return nil unless html

      count = bridge.send(:json_ld_item_count, html)
      return count if count && count >= MIN_ITEMS

      count = bridge.send(:repeating_element_count, html)
      return count if count && count >= MIN_ITEMS

      nil
    end

    def extract_feed(url)
      html = fetch_html(url)
      raise Stray::ExtractionError, "page fetch failed" unless html

      extract_feed_from_html(html, url)
    end

    def extract_feed_from_html(html, base_url)
      items = extract_json_ld_items(html, base_url)
      return items if items.any?

      extract_repeating_elements(html, base_url)
    end

    private

    def fetch_html(url_or_html)
      return url_or_html if url_or_html.include?("<html") || url_or_html.include?("<!DOCTYPE")

      response = PoliteCrawl.get(url_or_html, http_client: http_client)
      raise Stray::ExtractionError, "page fetch failed: #{response.status}" unless response.status == 200

      response.body
    end

    def http_client
      Faraday.new do |conn|
        conn.response :follow_redirects, max: 3
        conn.options.timeout = 30
        conn.options.open_timeout = 10
        conn.adapter :net_http
      end
    end

    def json_ld_item_count(html)
      items = extract_json_ld_items(html, "https://example.com")
      items.size if items.any?
    end

    def extract_json_ld_items(html, base_url)
      doc = Nokogiri::HTML(html)
      doc.css('script[type="application/ld+json"]').flat_map do |script|
        data = JSON.parse(script.content) rescue next
        arrays = data.is_a?(Array) ? data : [ data ]
        arrays.select { |d| d.is_a?(Hash) && d["@type"] == "ItemList" }
          .flat_map { |d| d["itemListElement"] || [] }
      end.compact.map do |element|
        map_json_ld_item(element, base_url)
      end.compact
    end

    def map_json_ld_item(element, base_url)
      return nil unless element.is_a?(Hash)

      url = element["url"]
      return nil unless url

      url = absolute_url(url, base_url)
      Stray::ExtractedContent.new(
        url: url,
        title: element["name"],
        content_text: nil,
        content_html: nil,
        thumbnail_url: element["image"],
        published_at: parse_date(element["datePublished"]),
        external_id: Digest::SHA256.hexdigest(url),
        duration: nil,
        creator_identity: nil,
        tags: []
      )
    end

    def repeating_element_count(html)
      items = extract_repeating_elements(html, "https://example.com")
      items.size if items.any?
    end

    def extract_repeating_elements(html, base_url)
      doc = Nokogiri::HTML(html)
      groups = doc.css("article, li, div").group_by { |el| "#{el.name}.#{el["class"]}" }
      best_group = groups.values.max_by { |group| group.size }

      return [] unless best_group && best_group.size >= MIN_ITEMS

      best_group.map { |el| map_repeating_element(el, base_url) }.compact
    end

    def map_repeating_element(element, base_url)
      link = element.at_css("a[href]")
      return nil unless link

      url = absolute_url(link["href"], base_url)
      title = element.at_css("h1, h2, h3, h4, .title")&.text&.strip || link.text&.strip
      thumbnail = element.at_css("img")&.[]("src")
      thumbnail = absolute_url(thumbnail, base_url) if thumbnail
      published = element.at_css("time[datetime]")&.[]("datetime")

      Stray::ExtractedContent.new(
        url: url,
        title: title,
        content_text: nil,
        content_html: nil,
        thumbnail_url: thumbnail,
        published_at: parse_date(published),
        external_id: Digest::SHA256.hexdigest(url),
        duration: nil,
        creator_identity: nil,
        tags: []
      )
    end

    def absolute_url(href, base_url)
      return nil unless href
      URI.join(base_url, href).to_s
    rescue URI::InvalidURIError
      href
    end

    def parse_date(value)
      return nil unless value
      Time.parse(value)
    rescue ArgumentError
      nil
    end
  end
end
