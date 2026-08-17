class Extractor
  FeedResult = Data.define(:items, :next_cursor, :has_more) do
    def initialize(items:, next_cursor:, has_more: false)
      super(items: items, next_cursor: next_cursor, has_more: has_more)
    end
  end
end
