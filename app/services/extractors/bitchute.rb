module Extractors
  class Bitchute < Extractor
    include HashMapper

    def self.matches?(url)
      Stray::Extractors::Bitchute.matches?(url)
    end

    def self.handles_kind?(kind)
      kind == "bitchute_channel"
    end

    def extract(url)
      map(Stray::Extractors::Bitchute.new.video_page(url))
    end

    def extract_feed(url)
      Stray::Extractors::Bitchute.new.channel_feed(url).map { |h| map(h) }
    end
  end
end
