require "json"
require "base64"
require "stray"

class CollectionManifest
  DEFAULT_PAGE_SIZE = 100
  NEXT_URL_PATH = "/c/%<slug>s/manifest.json"

  def self.build(collection, cursor: nil, page_size: DEFAULT_PAGE_SIZE, base_url: nil)
    new(collection, cursor, page_size, base_url).build
  end

  def initialize(collection, cursor, page_size, base_url)
    @collection = collection
    @page_size = page_size
    @base_url = base_url
    @offset = ManifestCursor.decode_offset(cursor)
  end

  def build
    items_scope = @collection.items.order(published_at: :desc)

    total = items_scope.count
    page_items = items_scope.offset(@offset).limit(@page_size).to_a

    has_more = (@offset + page_items.size) < total
    next_offset = @offset + page_items.size
    next_cursor = has_more ? ManifestCursor.encode_offset(next_offset) : nil
    path = format(NEXT_URL_PATH, slug: @collection.slug)

    {
      format: "stray-collection",
      version: 1,
      collection: {
        name: @collection.name,
        description: @collection.description,
        slug: @collection.slug,
        item_count: total
      },
      producer: {
        instance_name: Setting.get(:instance_name),
        instance_domain: Setting.get(:instance_domain),
        stray_version: Stray::VERSION
      },
      sources: sources_payload,
      items: page_items.map { |item| FeedItemPayload.payload(item) },
      pagination: {
        next_cursor: next_cursor,
        next_url: has_more ? ManifestCursor.next_url(base_url: @base_url, path: path, cursor: next_cursor) : nil,
        has_more: has_more
      }
    }
  end

  private

  def sources_payload
    @collection.sources.map do |source|
      { url: source.url, kind: source.kind, name: source.display_name, icon_url: source.icon_url }
    end
  end
end
