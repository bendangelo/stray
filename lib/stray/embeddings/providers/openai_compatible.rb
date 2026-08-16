require "faraday"

module Stray
  module Embeddings
    module Providers
      class OpenAICompatible
        def embed(text)
          response = http_client.post("/v1/embeddings", {
            model: embedding_model,
            input: Stray::Embeddings::Text.normalize(text)
          }.to_json)

          JSON.parse(response.body)["data"][0]["embedding"]
        end

        private

        def http_client
          Faraday.new(url: AppConfig.ai_provider[:url]) do |conn|
            conn.headers["Authorization"] = "Bearer #{AppConfig.ai_provider[:api_key]}"
            conn.headers["Content-Type"] = "application/json"
            conn.adapter :net_http
          end
        end

        def embedding_model
          Setting.get(:embedding_model).presence || "text-embedding-3-small"
        end
      end
    end
  end
end
