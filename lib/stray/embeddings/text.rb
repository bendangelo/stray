module Stray
  module Embeddings
    module Text
      MAX_WORDS = 512

      def self.normalize(content)
        return "" if content.nil? || content.empty?

        text = content.to_s.gsub(/<[^>]+>/, " ")
        text = text.gsub(/\s+/, " ").strip
        words = text.split
        words.first(MAX_WORDS).join(" ")
      end
    end
  end
end
