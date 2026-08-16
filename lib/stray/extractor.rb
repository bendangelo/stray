module Stray
  ExtractedContent = Data.define(
    :url, :title, :content_text, :content_html,
    :thumbnail_url, :published_at,
    :external_id, :duration,
    :creator_identity,
    :tags
  )

  CreatorIdentity = Data.define(:name, :url, :external_id, :thumbnail_url)

  class Extractor
    def self.matches?(url)
      raise NotImplementedError
    end

    def self.handles_kind?(kind)
      false
    end

    def extract(url)
      raise NotImplementedError
    end

    def extract_feed(url)
      raise NotImplementedError
    end
  end
end
