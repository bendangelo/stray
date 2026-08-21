module Bridges
  class Rumble < Stray::Bridge
    include HashMapper

    def self.matches?(url)
      Stray::Bridges::Rumble.matches?(url)
    end

    def self.handles_kind?(kind)
      kind == "rumble_channel"
    end

    def extract(url)
      map(Stray::Bridges::Rumble.new.video_page(url))
    end

    def extract_feed(url)
      Stray::Bridges::Rumble.new.channel_feed(url).map { |h| map(h) }
    end
  end
end
