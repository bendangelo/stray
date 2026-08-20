module Extractors
  class Peertube < Extractor
    include HashMapper

    def self.matches?(url)
      Stray::Extractors::Peertube.matches?(url)
    end

    def self.handles_kind?(kind)
      kind == "peertube_channel"
    end

    def extract(url)
      map(Stray::Extractors::Peertube.new.video_page(url))
    end

    def extract_feed(url)
      Stray::Extractors::Peertube.new.channel_feed(url).map { |h| map(h) }
    end
  end
end
