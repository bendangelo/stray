require "test_helper"

class Stray::Embeddings::Providers::OpenAICompatibleTest < ActiveSupport::TestCase
  setup do
    Setting.current.update!(
      ai_provider_name: "OPENAI_COMPATIBLE",
      ai_provider_url: "http://api:8080",
      ai_provider_api_key: "test-key",
      embedding_model: "text-embedding-3-small"
    )
    @provider = Stray::Embeddings::Providers::OpenAICompatible.new
  end

  test "embed calls OpenAI-compatible API and returns embedding" do
    response_body = {
      "data" => [ { "embedding" => [ 0.1, 0.2, 0.3 ] } ]
    }.to_json

    stub_request(:post, "http://api:8080/v1/embeddings")
      .with(
        body: { model: "text-embedding-3-small", input: "hello world" }.to_json,
        headers: { "Authorization" => "Bearer test-key" }
      )
      .to_return(status: 200, body: response_body)

    result = @provider.embed("hello world")

    assert_equal [ 0.1, 0.2, 0.3 ], result
  end
end
