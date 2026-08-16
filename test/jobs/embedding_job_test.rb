require "test_helper"

class EmbeddingJobTest < ActiveJob::TestCase
  setup do
    @item = items(:video_one)
  end

  test "embeds item and stores embedding blob" do
    provider = Object.new
    provider.define_singleton_method(:embed) { |_text| [ 0.1, 0.2, 0.3 ] }

    Stray::Embeddings::Provider.stub(:resolve, provider) do
      EmbeddingJob.perform_now("Item", @item.id)
    end

    @item.reload
    assert_not_nil @item.embedding
    result = Stray::Embeddings::Serializer.unpack(@item.embedding)
    assert_in_delta 0.1, result[0], 0.0001
  end

  test "skips if item already has embedding" do
    @item.update!(embedding: Stray::Embeddings::Serializer.pack([ 0.9 ]))
    provider = Object.new
    provider.define_singleton_method(:embed) { |_text| raise "should not be called" }

    Stray::Embeddings::Provider.stub(:resolve, provider) do
      EmbeddingJob.perform_now("Item", @item.id)
    end

    @item.reload
    assert_in_delta 0.9, Stray::Embeddings::Serializer.unpack(@item.embedding).first, 0.0001
  end

  test "rescues ModelMissing and leaves embedding nil" do
    provider = Object.new
    provider.define_singleton_method(:embed) { |_text| raise Stray::Embeddings::ModelMissing.new }

    Stray::Embeddings::Provider.stub(:resolve, provider) do
      EmbeddingJob.perform_now("Item", @item.id)
    end

    @item.reload
    assert_nil @item.embedding
  end

  test "embeds tag name and stores embedding" do
    tag = tags(:ruby)
    provider = Object.new
    provider.define_singleton_method(:embed) { |_text| [ 0.5, 0.5 ] }

    Stray::Embeddings::Provider.stub(:resolve, provider) do
      EmbeddingJob.perform_now("Tag", tag.id)
    end

    tag.reload
    assert_not_nil tag.embedding
  end

  test "enqueues TaggingJob after embedding item" do
    provider = Object.new
    provider.define_singleton_method(:embed) { |_text| [ 0.1 ] }
    Setting.current.update!(ai_provider_name: "NONE", llm_tagging_enabled: false)

    Stray::Embeddings::Provider.stub(:resolve, provider) do
      assert_enqueued_with(job: TaggingJob, args: [ @item.id ]) do
        EmbeddingJob.perform_now("Item", @item.id)
      end
    end
  end

  test "enqueues LlmTaggingJob when provider != NONE and enabled" do
    provider = Object.new
    provider.define_singleton_method(:embed) { |_text| [ 0.1 ] }
    Setting.current.update!(ai_provider_name: "OPENAI_COMPATIBLE", llm_tagging_enabled: true)

    Stray::Embeddings::Provider.stub(:resolve, provider) do
      assert_enqueued_with(job: LlmTaggingJob, args: [ @item.id ]) do
        EmbeddingJob.perform_now("Item", @item.id)
      end
    end
  ensure
    Setting.current.update!(ai_provider_name: "NONE", llm_tagging_enabled: false)
  end
end
