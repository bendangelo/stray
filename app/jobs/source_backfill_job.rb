class SourceBackfillJob < ApplicationJob
  include ItemUpsert
  queue_as :polling

  retry_on Stray::YtDlp::Error, wait: 1.minute, attempts: 2
  retry_on Stray::ExtractionError, wait: 1.minute, attempts: 3
  retry_on Stray::RateBudgetExhausted, wait: 15.seconds, attempts: 4

  def perform(source_id, cursor = nil)
    source = Source.find_by(id: source_id)
    return unless source&.active?
    return if source.backfilled_at.present? && cursor.nil?

    extractor = Stray::BridgeRegistry.find_for_source(source)
    return unless extractor&.respond_to?(:extract_backfill)

    result = extractor.extract_backfill(source.url, limit: backfill_limit, cursor: cursor)
    return if result.nil?

    contents, next_cursor, has_more = normalize_result(result)

    upsert_items(source, contents, extractor) if contents.any?

    if has_more && next_cursor.present?
      enqueue_next(source_id, next_cursor)
    else
      source.update!(backfilled_at: Time.current)
    end
  end

  private

  def normalize_result(result)
    if result.is_a?(Stray::Bridge::BackfillResult)
      [ result.items, result.next_cursor, result.has_more ]
    else
      [ Array(result), nil, false ]
    end
  end

  def enqueue_next(source_id, cursor)
    return if cursor.blank?

    self.class.set(wait: PoliteCrawl::RATE_BUDGET_INTERVAL.seconds).perform_later(source_id, cursor)
  end

  def backfill_limit
    Setting.get(:backfill_limit).to_i.positive? ? Setting.get(:backfill_limit).to_i : 50
  end
end
