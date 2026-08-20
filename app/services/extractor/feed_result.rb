class Extractor
  FeedResult = Data.define(:items, :next_cursor, :has_more, :collection_name, :producer_instance_name) do
    def initialize(items:, next_cursor:, has_more: false, collection_name: nil, producer_instance_name: nil)
      super(items: items, next_cursor: next_cursor, has_more: has_more,
            collection_name: collection_name, producer_instance_name: producer_instance_name)
    end
  end
end
