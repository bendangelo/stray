class EmbeddingJob < ApplicationJob
  queue_as :default

  def perform(record_type, record_id)
    case record_type
    when "Item" then embed_item(record_id)
    when "Tag"  then embed_tag(record_id)
    end
  end

  private

  def embed_item(item_id)
    item = Item.find_by(id: item_id)
    return unless item
    return if item.embedding.present?

    vec = provider.embed(item_text(item))
    item.update!(embedding: Stray::Embeddings::Serializer.pack(vec))
    enqueue_downstream(item_id)
  rescue Stray::Embeddings::ModelMissing => e
    Rails.logger.warn("[EmbeddingJob] Skipping item #{item_id}: #{e.message}")
  end

  def embed_tag(tag_id)
    tag = Tag.find_by(id: tag_id)
    return unless tag

    vec = provider.embed(Stray::Embeddings::Text.normalize(tag.name))
    tag.update!(embedding: Stray::Embeddings::Serializer.pack(vec))
  rescue Stray::Embeddings::ModelMissing => e
    Rails.logger.warn("[EmbeddingJob] Skipping tag #{tag_id}: #{e.message}")
  end

  def provider
    @provider ||= Stray::Embeddings::Provider.resolve
  end

  def item_text(item)
    Stray::Embeddings::Text.normalize(item.content_text || item.title)
  end

  def enqueue_downstream(item_id)
    TaggingJob.perform_later(item_id)

    if AppConfig.ai_provider[:name] != "NONE" && Setting.get(:llm_tagging_enabled)
      LlmTaggingJob.perform_later(item_id)
    end
  end
end
