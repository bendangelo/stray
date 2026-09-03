module Stray
  ExtractedContent = Data.define(
    :url, :title, :content_text, :content_html,
    :thumbnail_url, :published_at,
    :external_id, :duration,
    :creator_identity,
    :tags,
    :embed_id
  ) do
    def initialize(embed_id: nil, **kwargs)
      super(**kwargs, embed_id: embed_id)
    end
  end
end
