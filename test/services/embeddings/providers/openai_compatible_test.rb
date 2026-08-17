require "test_helper"

class Embeddings::Providers::OpenAICompatibleTest < ActiveSupport::TestCase
  setup do
    Setting.current.update!(
      ai_provider_name: "OPENAI_COMPATIBLE",
      ai_provider_url: "http://api:8080",
      ai_provider_api_key: "test-key",
      embedding_model: "text-embedding-3-small"
    )
    @provider = Embeddings::Providers::OpenAICompatible.new(
      url: "http://api:8080",
      api_key: "test-key",
      model: "text-embedding-3-small"
    )
  end

  test "embed calls OpenAI-compatible API and returns embedding" do
    VCR.use_cassette("providers/openai_embeddings") do
      result = @provider.embed("hello world")
      assert_equal [ 0.1, 0.2, 0.3 ], result
    end
  end
end
