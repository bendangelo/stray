module ItemUpsert
  extend ActiveSupport::Concern

  NO_MISSING_METADATA_UPDATE = %i[title url content_text content_html fetched_at].freeze

  private

  def upsert_items(source, contents, extractor = nil)
    return 0 if contents.empty?

    existing_ids = source.items.where(external_id: contents.map(&:external_id)).pluck(:external_id).to_set

    complete, incomplete = contents.partition { |c| c.duration.present? && c.thumbnail_url.present? && c.published_at.present? }

    id_by_external_id = {}
    id_by_external_id.merge!(upsert_rows(source, complete)) if complete.any?
    id_by_external_id.merge!(upsert_rows(source, incomplete, update_only: NO_MISSING_METADATA_UPDATE)) if incomplete.any?

    new_count = id_by_external_id.keys.count { |id| !existing_ids.include?(id) }

    needs_enrichment_ids = []
    contents.each do |content|
      item_id = id_by_external_id[content.external_id]
      apply_extractor_tags(source, item_id, content, extractor)
      EmbeddingJob.perform_later("Item", item_id)
      needs_enrichment_ids << item_id if content.duration.blank? || content.thumbnail_url.blank? || content.published_at.blank?
    end

    MetadataEnrichmentJob.perform_later(source.id, needs_enrichment_ids) if needs_enrichment_ids.any?
    new_count
  end

  def upsert_rows(source, batch, update_only: nil)
    rows = batch.map do |content|
      {
        source_id: source.id,
        user_id: source.user_id,
        external_id: content.external_id,
        title: content.title,
        url: content.url,
        content_text: content.content_text,
        content_html: content.content_html,
        thumbnail_url: content.thumbnail_url,
        duration: content.duration,
        published_at: content.published_at,
        fetched_at: Time.current,
        state: 0,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    opts = { unique_by: [ :source_id, :external_id ], returning: [ :id, :external_id ] }
    opts[:update_only] = update_only if update_only
    Item.upsert_all(rows, **opts).to_a.each_with_object({}) { |row, h| h[row["external_id"]] = row["id"] }
  end

  def apply_extractor_tags(source, item_id, content, extractor)
    tags = content.tags || []
    if tags.empty? && extractor&.respond_to?(:enrich_tags)
      item = Item.find(item_id)
      return if item.taggings.where(source: :user).exists?

      tags = Array(extractor.enrich_tags(content.url))
    end
    return unless tags.any?

    item ||= Item.find(item_id)
    tags.each do |name|
      tag = Tag.find_or_create_by!(user_id: source.user_id, name: name)
      Tagging.find_or_create_by!(item: item, tag: tag, source: :user)
      EmbeddingJob.perform_later("Tag", tag.id) if tag.embedding.nil?
    end
  end
end
