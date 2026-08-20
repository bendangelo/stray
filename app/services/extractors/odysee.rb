module Extractors
  class Odysee < Extractor
    include HashMapper

    def self.matches?(url)
      Stray::Extractors::Odysee.matches?(url)
    end

    def self.handles_kind?(kind)
      kind == "odysee_channel"
    end

    def extract(url)
      map(Stray::Extractors::Odysee.new.video_page(url))
    end

    def extract_feed(url)
      Stray::Extractors::Odysee.new.channel_feed(url).map { |h| map(h) }
    end
  end
end
