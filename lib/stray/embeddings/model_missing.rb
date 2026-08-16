module Stray
  module Embeddings
    class ModelMissing < StandardError
      def initialize(msg = "Embedding model file not found. Run bin/rails stray:embeddings:download")
        super
      end
    end

    class DownloadError < StandardError; end
  end
end
