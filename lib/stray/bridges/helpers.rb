require "time"
require "chronic"
require "chronic_duration"

module Stray
  module Bridges
    # Shared HTML/string normalization helpers for site extractors.
    # Pure Ruby — no Rails, no ActiveSupport. Ported from stray_video's Parsable.
    module Helpers
      module_function

      # Parse a humanized number or duration string into an Integer.
      # Handles "1.2k", "3m", "1,234", "3:45:12", "5 hours", "2 days".
      def dehumanize(value)
        return value if value.is_a?(Numeric)
        return 0 if value.nil?

        value = value.to_s.strip

        if value.match?(/\d+,\d+/)
          return value.delete(",").to_i
        end

        duration_parts = value.scan(/\d+/)
        if duration_parts.count == 3
          hours, minutes, seconds = duration_parts.map(&:to_i)
          return hours * 3600 + minutes * 60 + seconds
        end

        match = value.match(/([\d. ]+)([a-zA-Z]+)/)
        return time_to_seconds(value) unless match

        number = match[1].to_f
        unit = match[2].downcase

        case unit
        when "k" then number *= 1_000
        when "m" then number *= 1_000_000
        when "b" then number *= 1_000_000_000
        when "day", "days" then number *= 86_400
        when "hour", "hours" then number *= 3_600
        when "minute", "minutes" then number *= 60
        when "second", "seconds" then number *= 1
        end

        number.to_i
      end

      # Parse a humanized or ISO8601 time string into a Time, or nil.
      def dehumanize_time(value, nil_is_now: true)
        return Time.at(value) if value.is_a?(Numeric)
        return Time.now if value.nil? && nil_is_now
        return nil if value.nil?

        value = value.to_s.strip.gsub(",", "")

        if value.include?(" ago")
          seconds = ChronicDuration.parse(value)
          return Time.now - seconds if seconds
        end

        parsed = Time.parse(value)
        return parsed if parsed

        nil_is_now ? Time.now : nil
      rescue ArgumentError
        nil_is_now ? Time.now : nil
      end

      # Read a meta tag by name, property, or itemprop.
      def find_meta(doc, tag)
        doc.at("meta[name=\"#{tag}\"]")&.[]("content") ||
          doc.at("meta[property=\"#{tag}\"]")&.[]("content") ||
          doc.at("meta[itemprop=\"#{tag}\"]")&.[]("content")
      end

      # First non-empty title from meta/og:title/head title/h1.
      def find_title(doc)
        candidates = [
          find_meta(doc, "title"),
          find_meta(doc, "og:title"),
          doc.at("head title")&.text,
          doc.at("h1")&.text
        ]
        candidates.map { |c| c.to_s.strip.gsub(/\s+/, " ") }.find { |c| !c.empty? }
      end

      # First non-empty thumbnail from og:image/twitter:image/thumbnailUrl/video poster.
      def find_thumbnail(doc)
        candidates = [
          find_meta(doc, "og:image"),
          find_meta(doc, "twitter:image:src"),
          find_meta(doc, "thumbnailUrl"),
          doc.at("video")&.[]("poster")
        ]
        candidates.find { |c| !c.to_s.empty? }
      end

      # First non-empty description from meta/og:description/twitter:description.
      def find_description(doc)
        candidates = [
          find_meta(doc, "description"),
          find_meta(doc, "og:description"),
          find_meta(doc, "twitter:description")
        ]
        candidates.find { |c| !c.to_s.empty? }
      end

      # Parse a publish date from meta tags or a CSS selector.
      def find_publish_date(doc)
        candidates = [
          doc.at(".video-publish-date")&.text,
          find_meta(doc, "uploadDate"),
          find_meta(doc, "datePublished"),
          find_meta(doc, "article:published_time")
        ]
        time = candidates.map { |c| c.to_s.strip }.find { |c| !c.empty? }
        return nil if time.nil?

        Time.parse(time)
      rescue ArgumentError
        nil
      end

      # Parse a duration from meta tags.
      def find_duration(doc)
        dehumanize(find_meta(doc, "duration"))
      end

      # Resolve a possibly-relative URL against a base.
      def absolute_url(url, base:)
        return nil if url.nil? || url.empty?

        URI.join(base, url).to_s
      rescue URI::InvalidURIError
        url
      end

      # Strip scheme/host, keeping path (and optionally query).
      def clean_url(url, path_only: false, query: false)
        uri = URI.parse(url.to_s.strip)
        result = path_only ? uri.path.to_s : "#{uri.hostname}#{uri.path}"
        result += "?#{uri.query}" if query && !uri.query.nil? && !uri.query.empty?
        result
      rescue URI::InvalidURIError
        url.to_s
      end

      def time_to_seconds(time_str)
        parts = time_str.split(":").map(&:to_i)
        case parts.size
        when 1 then parts[0]
        when 2 then parts[0] * 60 + parts[1]
        when 3 then parts[0] * 3600 + parts[1] * 60 + parts[2]
        else 0
        end
      end
      private_class_method :time_to_seconds
    end
  end
end
