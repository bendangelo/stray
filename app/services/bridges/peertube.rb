module Bridges
  class Peertube < Stray::Bridge
    include HashMapper

    def self.matches?(url)
      Stray::Bridges::Peertube.matches?(url)
    end

    def self.handles_kind?(kind)
      kind == "peertube_channel"
    end

    def self.trust_level = :scraped_html
    def self.site_homepage = "https://joinpeertube.org"
    def self.last_tested_against = "2026-08"
    def self.author = "Stray"

    def extract(url)
      map(Stray::Bridges::Peertube.new.video_page(url))
    end

    def extract_feed(url)
      Stray::Bridges::Peertube.new.channel_feed(url).map { |h| map(h) }
    end

    def extract_backfill(url, limit:)
      core = Stray::Bridges::Peertube.new
      total = core.feed_total(url)
      return [] if total.zero?

      results = []
      start = 0
      while results.size < [ limit, total ].min
        page = core.channel_feed(url, start: start)
        break if page.empty?

        results.concat(page)
        start += page.size
      end
      results.first([ limit, total ].min).map { |h| map(h) }
    end

    # Reuse an already-fetched API response instead of re-requesting the feed.
    def extract_feed_from_response(response, url)
      if url.match?(%r{/api/v1/(video-channels|accounts)/[^/]+/videos})
        Stray::Bridges::Peertube.new.feed_from_response(response, url).map { |h| map(h) }
      else
        extract_feed(url)
      end
    end

    def enrich_tags(url)
      uri = URI.parse(url)
      uuid = uri.path.to_s.match(%r{/w/([^/]+)|/videos/watch/([^/]+)})&.captures&.compact&.first
      return nil unless uuid

      Stray::Bridges::Peertube.new.fetch_tags(uri.host, uuid)
    rescue URI::InvalidURIError
      nil
    end
  end
end
