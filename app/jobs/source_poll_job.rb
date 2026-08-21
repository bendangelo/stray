class SourcePollJob < ApplicationJob
  queue_as :polling

  NO_MISSING_METADATA_UPDATE = %i[title url content_text content_html fetched_at].freeze

  retry_on DomainMutex::LockTimeout, wait: 30.seconds, attempts: 3
  retry_on Stray::YtDlp::Error, wait: 1.minute, attempts: 2
  retry_on Stray::ExtractionError, wait: 1.minute, attempts: 3
  retry_on Stray::RateBudgetExhausted, wait: 15.seconds, attempts: 4

  discard_on DomainMutex::LockTimeout do |job, error|
    mark_source(job, error, :recovering)
  end

  discard_on Stray::YtDlp::Error do |job, error|
    mark_source(job, error, :recovering)
  end

  discard_on Stray::ExtractionError do |job, error|
    mark_source(job, error, :recovering)
  end

  discard_on Stray::RateBudgetExhausted do |job, error|
    mark_source(job, error, :recovering)
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
  rescue UrlGuard::Blocked => e
    Source::StatusMachine.mark_failed!(source, message: e.message)
    broadcast_source_update(source)
  rescue DomainMutex::LockTimeout, Stray::YtDlp::Error, Stray::ExtractionError, Stray::RateBudgetExhausted
    raise
  rescue StandardError => e
    Source::StatusMachine.mark_recovering!(source, message: e.message)
    broadcast_source_update(source)
  ensure
    if source&.persisted?
      source.update!(polling: false)
      broadcast_source_update(source)
    end
  end

  def self.mark_source(job, error, kind)
    source = Source.find_by(id: job.arguments.first)
    return unless source

    if kind == :recovering
      Source::StatusMachine.mark_recovering!(source, message: error.message)
    else
      Source::StatusMachine.mark_failed!(source, message: error.message)
    end
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_#{source.user_id}_sources",
      target: ActionView::RecordIdentifier.dom_id(source),
      partial: "sources/source",
      locals: { source: source }
    )
  end

  private

  def extract_and_persist(source)
    extractor = Stray::BridgeRegistry.find_for_source(source)
    raise Stray::YtDlp::ExtractionFailed, "No bridge for kind=#{source.kind} url=#{source.url}" unless extractor

    if extractor.class.respond_to?(:requires_auth?) && extractor.class.requires_auth?
      secrets = source.secrets.index_by(&:field_name)
      missing = extractor.class.secret_fields.map(&:to_s) - secrets.keys
      if missing.any?
        raise Stray::ExtractionError, "Bridge requires #{missing.join(', ')} secret(s); none configured"
      end
      extractor.secrets = secrets
    end

    cached = PoliteCrawl.get_with_cache(
      source.url,
      http_client: http_client,
      etag: source.etag,
      last_modified: source.last_modified
    )

    if cached == :not_modified
      source.recalculate_next_crawl!
      Source::StatusMachine.mark_ok!(source, etag: source.etag, last_modified: source.last_modified)
      return
    end

    contents = extract_contents(extractor, cached.response, source.url)
    contents = Array(contents)

    new_count = upsert_items(source, contents, extractor)
    track_empty_polls(source, new_count)
    backfill_source_metadata(source, contents)
    source.recalculate_next_crawl!
    if new_count > 0 || source.consecutive_empty_polls < 3
      Source::StatusMachine.mark_ok!(source, etag: cached.etag, last_modified: cached.last_modified)
    else
      Source::StatusMachine.mark_degraded!(source)
      source.update!(etag: cached.etag, last_modified: cached.last_modified)
    end
  rescue NotImplementedError => e
    Source::StatusMachine.mark_failed!(source, message: "Bridge missing extract_feed: #{e.message}")
    reschedule_on_failure!(source)
  rescue Stray::YtDlp::Error, Stray::ExtractionError
    raise
  rescue UrlGuard::Blocked => e
    Source::StatusMachine.mark_failed!(source, message: e.message)
  rescue StandardError => e
    Source::StatusMachine.mark_recovering!(source, message: e.message)
  end

  def track_empty_polls(source, new_count)
    if new_count > 0
      source.update!(consecutive_empty_polls: 0)
      return
    end

    predicted = source.predicted_publish_at
    return if predicted && Time.current < predicted

    source.update!(consecutive_empty_polls: source.consecutive_empty_polls + 1)
  end

  def extract_contents(extractor, response, url)
    if extractor.respond_to?(:extract_feed_from_response)
      extractor.extract_feed_from_response(response, url)
    else
      extractor.extract_feed(url)
    end
  end

  def http_client
    Faraday.new do |conn|
      conn.response :follow_redirects, max: 3
      conn.options.timeout = 30
      conn.options.open_timeout = 10
      conn.adapter :net_http
    end
  end

  def extract_and_persist_relay(source, cursor)
    extractor = Stray::BridgeRegistry.find_for_source(source)
    raise Stray::YtDlp::ExtractionFailed, "No bridge for kind=#{source.kind}" unless extractor

    fetch_url = cursor ? "#{source.url}?cursor=#{cursor}" : source.url
    result = extractor.extract_feed(fetch_url)

    if result.is_a?(Stray::Bridge::FeedResult)
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

    Source::StatusMachine.mark_ok!(source, etag: source.etag, last_modified: source.last_modified)
    source.recalculate_next_crawl!
  end

  def update_relay_error(source, message)
    Source::StatusMachine.mark_recovering!(source, message: message)
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
