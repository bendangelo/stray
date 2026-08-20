module Extractors
  # Maps a normalized Hash (from a Stray::Extractors core) into a
  # Stray::ExtractedContent, rendering extra fields into a summary block.
  module HashMapper
    def map(hash)
      return nil if hash.nil?

      Stray::ExtractedContent.new(
        url: hash[:url],
        title: hash[:title],
        content_text: summary_text(hash),
        content_html: summary_html(hash),
        thumbnail_url: hash[:thumbnail_url],
        published_at: hash[:published_at],
        external_id: hash[:external_id],
        duration: hash[:duration],
        creator_identity: map_creator(hash[:creator_identity]),
        tags: hash[:tags] || []
      )
    end

    def map_creator(identity)
      return nil unless identity

      Stray::CreatorIdentity.new(
        name: identity[:name],
        url: identity[:url],
        external_id: identity[:external_id],
        thumbnail_url: identity[:thumbnail_url]
      )
    end

    def summary_text(hash)
      parts = []
      parts << "Duration: #{hash[:duration]}s" if hash[:duration]
      parts << "Views: #{hash[:views]}" if hash[:views]
      parts << "Live" if hash[:live]
      parts << "Short" if hash[:is_short]
      parts.join("\n")
    end

    def summary_html(hash)
      parts = []
      parts << "<b>Duration:</b> #{hash[:duration]}s" if hash[:duration]
      parts << "<b>Views:</b> #{hash[:views]}" if hash[:views]
      parts << "<b>Live</b>" if hash[:live]
      parts << "<b>Short</b>" if hash[:is_short]
      parts.join("<br>")
    end
  end
end
