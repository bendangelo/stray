module Bridges
  class Bitchute < Stray::Bridge
    include HashMapper

    def self.matches?(url)
      Stray::Bridges::Bitchute.matches?(url)
    end

    def self.handles_kind?(kind)
      kind == "bitchute_channel"
    end

    def self.trust_level = :scraped_html
    def self.site_homepage = "https://www.bitchute.com"
    def self.last_tested_against = "2026-08"
    def self.author = "Stray"

    def extract(url)
      map(Stray::Bridges::Bitchute.new.video_page(url))
    end

    def extract_feed(url)
      Stray::Bridges::Bitchute.new.channel_feed(url).map { |h| map(h) }
    end
  end
end
