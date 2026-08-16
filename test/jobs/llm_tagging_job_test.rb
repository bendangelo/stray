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
    response_body = { "choices" => [ { "message" => { "content" => '["ruby", "testing"]' } } ] }.to_json
    stub_request(:post, "http://api:8080/v1/chat/completions")
      .to_return(status: 200, body: response_body)

    LlmTaggingJob.perform_now(@item.id)

    assert @item.taggings.where(source: :ai_llm).count >= 2
    assert Tag.exists?(user: users(:one), name: "ruby")
    assert Tag.exists?(user: users(:one), name: "testing")
  end

  test "creates new tags and enqueues embedding job" do
    response_body = { "choices" => [ { "message" => { "content" => '["newtag"]' } } ] }.to_json
    stub_request(:post, "http://api:8080/v1/chat/completions")
      .to_return(status: 200, body: response_body)

    assert_enqueued_with(job: EmbeddingJob) do
      LlmTaggingJob.perform_now(@item.id)
    end
  end

  test "does not duplicate existing tags" do
    Tag.create!(user: users(:one), name: "existingtag")
    response_body = { "choices" => [ { "message" => { "content" => '["existingtag"]' } } ] }.to_json
    stub_request(:post, "http://api:8080/v1/chat/completions")
      .to_return(status: 200, body: response_body)

    LlmTaggingJob.perform_now(@item.id)

    assert_equal 1, Tag.where(user: users(:one), name: "existingtag").count
  end
end
