class SourceBackfillJob < ApplicationJob
  include ItemUpsert
  queue_as :polling

  retry_on Stray::YtDlp::Error, wait: 1.minute, attempts: 2
  retry_on Stray::ExtractionError, wait: 1.minute, attempts: 3
  retry_on Stray::RateBudgetExhausted, wait: 15.seconds, attempts: 4

  def perform(source_id)
    source = Source.find_by(id: source_id)
    return unless source&.active?
    return if source.backfilled_at.present?

    extractor = Stray::BridgeRegistry.find_for_source(source)
    return unless extractor&.respond_to?(:extract_backfill)

    contents = Array(extractor.extract_backfill(source.url, limit: backfill_limit))
    return if contents.empty?

    upsert_items(source, contents, extractor)
    source.update!(backfilled_at: Time.current)
  end

  private

  def backfill_limit
    Setting.get(:backfill_limit).to_i.positive? ? Setting.get(:backfill_limit).to_i : 50
  end
end
