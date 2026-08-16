module Stray
  class ExtractorRegistry
    @extractors = []

    class << self
      def register(extractor_class)
        @extractors << extractor_class unless @extractors.include?(extractor_class)
      end

      def find_for(url)
        @extractors.find { |klass| klass.matches?(url) }&.new
      end

      def find_for_source(source)
        @extractors.find { |klass| klass.handles_kind?(source.kind) }&.new
      end

      def all
        @extractors.dup
      end

      def reset!
        @extractors = []
      end
    end
  end
end
