require "test_helper"

class TaggingJobTest < ActiveJob::TestCase
  setup do
    @item = Item.create!(
      source: sources(:youtube), user: users(:one),
      external_id: "tagjob1", title: "Tag Job Item", url: "https://example.com/tagjob1"
    )
    Setting.current.update!(zero_shot_threshold: 0.35, zero_shot_top_n: 5)
  end

  test "skips if item has no embedding" do
    @item.update!(embedding: nil)
    TaggingJob.perform_now(@item.id)
    assert_equal 0, @item.taggings.where(source: :ai_embedding).count
  end

  test "cold-start no-op when no tags have embeddings" do
    @item.update!(embedding: Embeddings::Serializer.pack([ 1.0, 0.0 ]))
    TaggingJob.perform_now(@item.id)
    assert_equal 0, @item.taggings.count
  end

  test "assigns tags above threshold" do
    @item.update!(embedding: Embeddings::Serializer.pack([ 1.0, 0.0 ]))
    tags(:ruby).update!(embedding: Embeddings::Serializer.pack([ 0.9, 0.1 ]))
    tags(:rails).update!(embedding: Embeddings::Serializer.pack([ 0.1, 0.9 ]))

    TaggingJob.perform_now(@item.id)

    ruby_tagging = @item.taggings.find_by(tag: tags(:ruby))
    assert ruby_tagging
    assert_equal "ai_embedding", ruby_tagging.source
    assert_not_nil ruby_tagging.score
    assert_in_delta 1.0, ruby_tagging.score, 0.01
  end

  test "does not assign tags below threshold" do
    @item.update!(embedding: Embeddings::Serializer.pack([ 1.0, 0.0 ]))
    tags(:ruby).update!(embedding: Embeddings::Serializer.pack([ 0.0, 1.0 ]))
    Setting.current.update!(zero_shot_threshold: 0.9)

    TaggingJob.perform_now(@item.id)

    assert_nil @item.taggings.find_by(tag: tags(:ruby), source: :ai_embedding)
  end

  test "caps at top_n" do
    @item.update!(embedding: Embeddings::Serializer.pack([ 1.0, 0.0 ]))
    Setting.current.update!(zero_shot_top_n: 1)
    tags(:ruby).update!(embedding: Embeddings::Serializer.pack([ 0.9, 0.1 ]))
    tags(:rails).update!(embedding: Embeddings::Serializer.pack([ 0.9, 0.1 ]))
    tags(:ai).update!(embedding: Embeddings::Serializer.pack([ 0.9, 0.1 ]))

    TaggingJob.perform_now(@item.id)

    assert_equal 1, @item.taggings.where(source: :ai_embedding).count
  end

  test "idempotent — does not duplicate existing tagging" do
    @item.update!(embedding: Embeddings::Serializer.pack([ 1.0, 0.0 ]))
    tags(:ruby).update!(embedding: Embeddings::Serializer.pack([ 0.9, 0.1 ]))
    TaggingJob.perform_now(@item.id)
    TaggingJob.perform_now(@item.id)

    assert_equal 1, @item.taggings.where(tag: tags(:ruby), source: :ai_embedding).count
  end
end
