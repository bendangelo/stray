module Stray
  class BridgeRegistry
    @bridges = []

    class << self
      def register(bridge_class)
        @bridges << bridge_class unless @bridges.include?(bridge_class)
      end

      def find_for(url)
        @bridges.find { |klass| klass.matches?(url) }&.new
      end

      def find_for_source(source)
        @bridges.find { |klass| klass.handles_kind?(source.kind) }&.new
      end

      def all
        @bridges.dup
      end

      def reset!
        @bridges = []
      end
    end
  end
end
