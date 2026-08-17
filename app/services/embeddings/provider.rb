module Embeddings
  module Provider
    def self.resolve
      case AppConfig.ai_provider[:name]
      when "OPENAI_COMPATIBLE"
        Providers::OpenAICompatible.new(
          url: AppConfig.ai_provider[:url],
          api_key: AppConfig.ai_provider[:api_key],
          model: Setting.get(:embedding_model).presence || "text-embedding-3-small"
        )
      else
        Providers::LocalMiniLM.new(
          model_path: Rails.root.join("storage/embeddings/all-MiniLM-L6-v2.onnx"),
          vocab_path: Rails.root.join("app/services/embeddings/vocab.txt")
        )
      end
    end
  end
end
