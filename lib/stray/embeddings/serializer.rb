module Stray
  module Embeddings
    module Serializer
      def self.pack(array)
        array.pack("e*")
      end

      def self.unpack(blob)
        return [] if blob.nil? || blob.empty?

        blob.unpack("e*")
      end
    end
  end
end
