class SourcePollJob < ApplicationJob
  queue_as :polling

  retry_on Stray::YtDlp::Error, wait: 1.minute, attempts: 2

  discard_on Stray::YtDlp::Error do |job, error|
    source = Source.find_by(id: job.arguments.first)
    return unless source

    source.update!(last_error: error.message, last_error_at: Time.current)
  end

  def perform(source_id)
    source = Source.find_by(id: source_id)
    return unless source&.active?

    domain = Stray::DomainMutex.domain_for(source.url)

    Stray::DomainMutex.with_lock(domain) do
      extract_and_persist(source)
    end
  end

  private

  def extract_and_persist(source)
    extractor = Stray::ExtractorRegistry.find_for(source.url)
    raise Stray::YtDlp::ExtractionFailed, "No extractor found for #{source.url}" unless extractor

    contents = extractor.extract(source.url)
    contents = Array(contents)

    upsert_items(source, contents)
    source.recalculate_next_crawl!
    source.update!(last_polled_at: Time.current, last_error: nil, last_error_at: nil)
  end

  def upsert_items(source, contents)
    return if contents.empty?

    rows = contents.map do |content|
      {
        source_id: source.id,
        user_id: source.user_id,
        external_id: content.external_id,
        title: content.title,
        url: build_item_url(source, content),
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

    Item.upsert_all(rows, unique_by: [ :source_id, :external_id ], returning: :id).then do |result|
      item_ids = result.to_a.map { |row| row["id"] }

      contents.each_with_index do |content, i|
        item_id = item_ids[i]
        apply_extractor_tags(source, item_id, content)
        EmbeddingJob.perform_later("Item", item_id)
      end
    end
  end

  def apply_extractor_tags(source, item_id, content)
    return unless content.tags&.any?

    item = Item.find(item_id)
    content.tags.each do |name|
      tag = Tag.find_or_create_by!(user_id: source.user_id, name: name)
      Tagging.find_or_create_by!(item: item, tag: tag, source: :user)
      EmbeddingJob.perform_later("Tag", tag.id) if tag.embedding.nil?
    end
  end

  def build_item_url(source, content)
    return content.external_id if content.external_id&.start_with?("http")

    case source.kind
    when "youtube_channel"
      "https://www.youtube.com/watch?v=#{content.external_id}"
    else
      "https://example.com/watch/#{content.external_id}"
    end
  end
end
