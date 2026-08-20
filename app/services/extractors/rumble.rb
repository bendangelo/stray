module Extractors
  class Rumble < Extractor
    include HashMapper

    def self.matches?(url)
      Stray::Extractors::Rumble.matches?(url)
    end

    def self.handles_kind?(kind)
      kind == "rumble_channel"
    end

    def extract(url)
      map(Stray::Extractors::Rumble.new.video_page(url))
    end

    def extract_feed(url)
      Stray::Extractors::Rumble.new.channel_feed(url).map { |h| map(h) }
    end
  end
end
