require "json"
require "base64"
require "stray"

module Stray
  class CollectionManifest
    DEFAULT_PAGE_SIZE = 100
    CURSOR_HEADER = "sc1"

    def self.build(collection, cursor: nil, page_size: DEFAULT_PAGE_SIZE, base_url: nil)
      new(collection, cursor, page_size, base_url).build
    end

    def initialize(collection, cursor, page_size, base_url)
      @collection = collection
      @page_size = page_size
      @base_url = base_url
      @offset = decode_offset(cursor)
    end

    def build
      items_scope = @collection.items
        .where.not(state: :hidden)
        .order(published_at: :desc)

      total = items_scope.count
      page_items = items_scope.offset(@offset).limit(@page_size).to_a

      has_more = (@offset + page_items.size) < total
      next_offset = @offset + page_items.size
      next_cursor = has_more ? encode_offset(next_offset) : nil

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
        items: page_items.map { |item| item_payload(item) },
        pagination: {
          next_cursor: next_cursor,
          next_url: has_more ? next_url(next_cursor) : nil,
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

    def item_payload(item)
      {
        external_id: item.external_id,
        title: item.title,
        url: item.url,
        content_text: item.content_text,
        content_html: item.content_html,
        thumbnail_url: item.thumbnail_url,
        published_at: item.published_at&.iso8601,
        duration: item.duration,
        tags: item_tags(item)
      }
    end

    def item_tags(item)
      item.tags.pluck(:name)
    end

    def decode_offset(cursor)
      return 0 if cursor.blank?
      decoded = Base64.urlsafe_decode64(cursor.to_s)
      payload = JSON.parse(decoded)
      raise "invalid cursor" unless payload["h"] == CURSOR_HEADER
      payload["o"].to_i
    rescue ArgumentError, JSON::ParserError
      0
    end

    def encode_offset(offset)
      Base64.urlsafe_encode64(JSON.generate({ h: CURSOR_HEADER, o: offset }))
    end

    def next_url(cursor)
      path = "/c/#{@collection.slug}/manifest.json"
      if @base_url
        "#{@base_url}#{path}?cursor=#{cursor}"
      else
        "#{path}?cursor=#{cursor}"
      end
    end
  end
end
