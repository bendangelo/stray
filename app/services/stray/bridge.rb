module Stray
  class Bridge
    def self.matches?(url)        = raise NotImplementedError
    def self.handles_kind?(kind)  = false
    def extract(url)              = raise NotImplementedError
    def extract_feed(url)         = raise NotImplementedError
    def enrich_tags(url)          = nil

    def extract_feed_from_response(response, url)
      extract_feed(url)
    end

    def self.trust_level          = :scraped_html
    def self.site_homepage        = nil
    def self.last_tested_against  = nil
    def self.requires_auth?       = false
    def self.secret_fields         = []
    def self.author               = nil
    def self.source_url           = nil
    def self.license              = "AGPL-3.0"
  end
end
