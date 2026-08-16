require "test_helper"

class LlmTaggingJobTest < ActiveJob::TestCase
  setup do
    @item = items(:video_one)
    Setting.current.update!(
      ai_provider_name: "OPENAI_COMPATIBLE",
      ai_provider_url: "http://api:8080",
      ai_provider_api_key: "test-key",
      llm_tagging_enabled: true,
      llm_tagging_model: "gpt-4o-mini"
    )
  end

  teardown do
    Setting.current.update!(ai_provider_name: "NONE", llm_tagging_enabled: false)
  end

  test "skips when provider is NONE" do
    Setting.current.update!(ai_provider_name: "NONE")
    LlmTaggingJob.perform_now(@item.id)
    assert_equal 0, @item.taggings.where(source: :ai_llm).count
  end

  test "skips when llm_tagging_enabled is false" do
    Setting.current.update!(llm_tagging_enabled: false)
    LlmTaggingJob.perform_now(@item.id)
    assert_equal 0, @item.taggings.where(source: :ai_llm).count
  end

  test "creates taggings from LLM response" do
    VCR.use_cassette("llm_tagging/create_taggings") do
      LlmTaggingJob.perform_now(@item.id)
    end

    assert @item.taggings.where(source: :ai_llm).count >= 2
    assert Tag.exists?(user: users(:one), name: "ruby")
    assert Tag.exists?(user: users(:one), name: "testing")
  end

  test "creates new tags and enqueues embedding job" do
    VCR.use_cassette("llm_tagging/create_new_tags") do
      assert_enqueued_with(job: EmbeddingJob) do
        LlmTaggingJob.perform_now(@item.id)
      end
    end
  end

  test "does not duplicate existing tags" do
    Tag.create!(user: users(:one), name: "existingtag")

    VCR.use_cassette("llm_tagging/no_duplicate") do
      LlmTaggingJob.perform_now(@item.id)
    end

    assert_equal 1, Tag.where(user: users(:one), name: "existingtag").count
  end
end
