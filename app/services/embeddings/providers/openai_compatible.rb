require "faraday"

module Embeddings
  module Providers
    class OpenAICompatible
      def initialize(url:, api_key:, model:)
        @url = url
        @api_key = api_key
        @model = model
      end

      def embed(text)
        response = http_client.post("/v1/embeddings", {
          model: @model,
          input: Embeddings::Text.normalize(text)
        }.to_json)

        JSON.parse(response.body)["data"][0]["embedding"]
      end

      private

      def http_client
        Faraday.new(url: @url) do |conn|
          conn.headers["Authorization"] = "Bearer #{@api_key}"
          conn.headers["Content-Type"] = "application/json"
          conn.adapter :net_http
        end
      end
    end
  end
end
