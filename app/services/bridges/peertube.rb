module Bridges
  class Peertube < Stray::Bridge
    include HashMapper

    def self.matches?(url)
      Stray::Bridges::Peertube.matches?(url)
    end

    def self.handles_kind?(kind)
      kind == "peertube_channel"
    end

    def extract(url)
      map(Stray::Bridges::Peertube.new.video_page(url))
    end

    def extract_feed(url)
      Stray::Bridges::Peertube.new.channel_feed(url).map { |h| map(h) }
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
