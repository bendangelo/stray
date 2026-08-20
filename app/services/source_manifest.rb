require "stray"

class SourceManifest
  DEFAULT_PAGE_SIZE = 100
  NEXT_URL_PATH = "/s/%<slug>s/manifest.json"

  def self.build(source, cursor: nil, page_size: DEFAULT_PAGE_SIZE, base_url: nil)
    new(source, cursor, page_size, base_url).build
  end

  def initialize(source, cursor, page_size, base_url)
    @source = source
    @page_size = page_size
    @base_url = base_url
    @offset = ManifestCursor.decode_offset(cursor)
  end

  def build
    items_scope = @source.items.order(published_at: :desc)

    total = items_scope.count
    page_items = items_scope.offset(@offset).limit(@page_size).to_a

    has_more = (@offset + page_items.size) < total
    next_offset = @offset + page_items.size
    next_cursor = has_more ? ManifestCursor.encode_offset(next_offset) : nil
    path = format(NEXT_URL_PATH, slug: @source.slug)

    {
      format: "stray-source",
      version: 1,
      source: {
        name: @source.display_name,
        url: @source.url,
        kind: @source.kind,
        icon_url: @source.icon_url,
        slug: @source.slug,
        item_count: total
      },
      producer: {
        instance_name: Setting.get(:instance_name),
        instance_domain: Setting.get(:instance_domain),
        stray_version: Stray::VERSION
      },
      items: page_items.map { |item| FeedItemPayload.payload(item) },
      pagination: {
        next_cursor: next_cursor,
        next_url: has_more ? ManifestCursor.next_url(base_url: @base_url, path: path, cursor: next_cursor) : nil,
        has_more: has_more
      }
    }
  end
end
