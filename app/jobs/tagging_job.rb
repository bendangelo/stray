class TaggingJob < ApplicationJob
  queue_as :default

  def perform(item_id)
    item = Item.find_by(id: item_id)
    return unless item
    return unless item.embedding

    item_embedding = Stray::Embeddings::Serializer.unpack(item.embedding)
    candidate_tags = Tag.where(user_id: item.user_id).where.not(embedding: nil)

    return if candidate_tags.empty?

    scored = candidate_tags.map do |tag|
      tag_vec = Stray::Embeddings::Serializer.unpack(tag.embedding)
      { tag: tag, score: Stray::Embeddings::Cosine.similarity(item_embedding, tag_vec) }
    end

    threshold = Setting.get(:zero_shot_threshold) || 0.35
    top_n = Setting.get(:zero_shot_top_n) || 5

    scored.select { |s| s[:score] && s[:score] >= threshold }
      .sort_by { |s| -s[:score] }
      .first(top_n)
      .each do |s|
        Tagging.find_or_create_by!(item: item, tag: s[:tag], source: :ai_embedding) do |t|
          t.score = s[:score]
        end
      end
  end
end
