module Bridges
  class Odysee < Stray::Bridge
    include HashMapper

    def self.matches?(url)
      Stray::Bridges::Odysee.matches?(url)
    end

    def self.handles_kind?(kind)
      kind == "odysee_channel"
    end

    def self.trust_level = :hidden_rss
    def self.site_homepage = "https://odysee.com"
    def self.last_tested_against = "2026-08"
    def self.author = "Stray"

    def extract(url)
      map(Stray::Bridges::Odysee.new.video_page(url))
    end

    def extract_feed(url)
      Stray::Bridges::Odysee.new.channel_feed(url).map { |h| map(h) }
    end
  end
end
