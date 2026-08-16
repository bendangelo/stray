require "test_helper"

class Stray::Embeddings::ProviderTest < ActiveSupport::TestCase
  setup do
    @original_provider = AppConfig.ai_provider[:name]
  end

  teardown do
    Setting.current.update!(ai_provider_name: @original_provider)
  end

  test "resolve returns LocalMiniLM for NONE" do
    Setting.current.update!(ai_provider_name: "NONE")
    assert_instance_of Stray::Embeddings::Providers::LocalMiniLM,
                       Stray::Embeddings::Provider.resolve
  end

  test "resolve returns OpenAICompatible for OPENAI_COMPATIBLE" do
    Setting.current.update!(ai_provider_name: "OPENAI_COMPATIBLE", ai_provider_url: "http://localhost:8080")
    assert_instance_of Stray::Embeddings::Providers::OpenAICompatible,
                       Stray::Embeddings::Provider.resolve
  end

  test "resolve returns LocalMiniLM for OLLAMA (not an embedding provider)" do
    Setting.current.update!(ai_provider_name: "OLLAMA", ai_provider_url: "http://ollama:11434")
    assert_instance_of Stray::Embeddings::Providers::LocalMiniLM,
                       Stray::Embeddings::Provider.resolve
  end
end
