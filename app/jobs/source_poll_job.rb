class SourcePollJob < ApplicationJob
  queue_as :polling

  NO_MISSING_METADATA_UPDATE = %i[title url content_text content_html fetched_at].freeze

  retry_on Stray::YtDlp::Error, wait: 1.minute, attempts: 2
  retry_on Stray::ExtractionError, wait: 1.minute, attempts: 3

  discard_on Stray::YtDlp::Error do |job, error|
    source = Source.find_by(id: job.arguments.first)
    return unless source

    source.update!(last_error: error.message, last_error_at: Time.current, status: :failed, next_crawl_at: 5.minutes.from_now)
  end

  discard_on Stray::ExtractionError do |job, error|
    source = Source.find_by(id: job.arguments.first)
    return unless source

    source.update!(last_error: error.message, last_error_at: Time.current, status: :failed, next_crawl_at: 5.minutes.from_now)
  end

  def perform(source_id, cursor = nil)
    source = Source.find_by(id: source_id)
    return unless source&.active?

    source.update!(polling: true)
    broadcast_source_update(source)

    source = Youtube::PendingChannelResolver.call(source)

    domain = DomainMutex.domain_for(source.url)

    if source.kind == "stray_collection"
      extract_and_persist_relay(source, cursor)
    else
      DomainMutex.with_lock(domain) do
        extract_and_persist(source)
      end
    end
  ensure
    if source&.persisted?
      source.update!(polling: false)
      broadcast_source_update(source)
    end
  end

  private

  def extract_and_persist(source)
    extractor = ExtractorRegistry.find_for_source(source)
    raise Stray::YtDlp::ExtractionFailed, "No extractor for kind=#{source.kind} url=#{source.url}" unless extractor

    contents = extractor.extract_feed(source.url)
    contents = Array(contents)

    upsert_items(source, contents, extractor)
    backfill_source_metadata(source, contents)
    source.recalculate_next_crawl!
    source.update!(last_polled_at: Time.current, last_error: nil, last_error_at: nil, status: :ok)
  rescue NotImplementedError => e
    source.update!(last_error: "Extractor missing extract_feed: #{e.message}", last_error_at: Time.current, status: :failed)
    reschedule_on_failure!(source)
  rescue Stray::YtDlp::Error, Stray::ExtractionError
    raise
  rescue StandardError => e
    source.update!(last_error: e.message, last_error_at: Time.current, status: :failed)
    reschedule_on_failure!(source)
  end

  def extract_and_persist_relay(source, cursor)
    extractor = ExtractorRegistry.find_for_source(source)
    raise Stray::YtDlp::ExtractionFailed, "No extractor for kind=#{source.kind}" unless extractor

    fetch_url = cursor ? "#{source.url}?cursor=#{cursor}" : source.url
    result = extractor.extract_feed(fetch_url)

    if result.is_a?(Extractor::FeedResult)
      handle_feed_result(source, result, cursor)
    else
      upsert_items(source, Array(result))
      finish_relay_sync(source, cursor)
    end
  rescue UrlGuard::Blocked, StandardError => e
    update_relay_error(source, e.message)
  end

  def handle_feed_result(source, result, cursor)
    if early_stop?(source, result.items)
      finish_relay_sync(source, cursor, result)
      return
    end

    upsert_items(source, result.items)

    if result.has_more && result.next_cursor.present?
      SourcePollJob.perform_later(source.id, result.next_cursor)
    else
      finish_relay_sync(source, cursor, result)
    end
  end

  def early_stop?(source, items)
    return false if items.empty?
    external_ids = items.map(&:external_id)
    existing = source.items.where(external_id: external_ids).pluck(:external_id).to_set
    external_ids.all? { |id| existing.include?(id) }
  end

  def finish_relay_sync(source, cursor, result = nil)
    rc = source.remote_collection
    return unless rc

    updates = {
      last_synced_at: Time.current,
      item_count: source.items.count,
      last_cursor: cursor,
      last_error: nil,
      last_error_at: nil
    }

    if result&.collection_name
      updates[:collection_name] = result.collection_name
      updates[:producer_instance_name] = result.producer_instance_name
    end

    rc.update!(updates)

    if result&.collection_name && source.name == "Remote collection"
      source.update!(name: result.collection_name)
    end

    source.update!(last_polled_at: Time.current, last_error: nil, last_error_at: nil, status: :ok)
    source.recalculate_next_crawl!
  end

  def update_relay_error(source, message)
    source.update!(last_error: message, last_error_at: Time.current, status: :failed, next_crawl_at: 5.minutes.from_now)
    rc = source.remote_collection
    rc&.update!(last_error: message, last_error_at: Time.current)
  end

  def backfill_source_metadata(source, contents)
    updates = {}
    if source.name.nil?
      creator = contents.map(&:creator_identity).compact.find { |c| c.name }
      updates[:name] = creator.name if creator
    end
    if source.icon_url.nil?
      creator = contents.map(&:creator_identity).compact.find { |c| c.thumbnail_url }
      updates[:icon_url] = creator.thumbnail_url if creator
    end
    source.update!(updates) if updates.any?
  end

  def upsert_items(source, contents, extractor = nil)
    return if contents.empty?

    complete, incomplete = contents.partition { |c| c.duration.present? && c.thumbnail_url.present? && c.published_at.present? }

    id_by_external_id = {}
    id_by_external_id.merge!(upsert_rows(source, complete)) if complete.any?
    id_by_external_id.merge!(upsert_rows(source, incomplete, update_only: NO_MISSING_METADATA_UPDATE)) if incomplete.any?

    needs_enrichment_ids = []
    contents.each do |content|
      item_id = id_by_external_id[content.external_id]
      apply_extractor_tags(source, item_id, content, extractor)
      EmbeddingJob.perform_later("Item", item_id)
      needs_enrichment_ids << item_id if content.duration.blank? || content.thumbnail_url.blank? || content.published_at.blank?
    end

    MetadataEnrichmentJob.perform_later(source.id, needs_enrichment_ids) if needs_enrichment_ids.any?
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

  def broadcast_source_update(source)
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_#{source.user_id}_sources",
      target: ActionView::RecordIdentifier.dom_id(source),
      partial: "sources/source",
      locals: { source: source }
    )
  end

  def reschedule_on_failure!(source)
    source.update!(next_crawl_at: 5.minutes.from_now)
  end
end
