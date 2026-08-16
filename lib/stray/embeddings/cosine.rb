module Stray
  module Embeddings
    module Cosine
      def self.similarity(a, b)
        return nil if a.empty? || b.empty?

        dot = 0.0
        mag_a = 0.0
        mag_b = 0.0

        a.each_with_index do |val, i|
          dot += val * b[i]
          mag_a += val * val
          mag_b += b[i] * b[i]
        end

        return nil if mag_a.zero? || mag_b.zero?

        dot / (Math.sqrt(mag_a) * Math.sqrt(mag_b))
      end
    end
  end
end
