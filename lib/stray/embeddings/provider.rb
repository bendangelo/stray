module Stray
  module Embeddings
    module Provider
      def self.resolve
        case AppConfig.ai_provider[:name]
        when "OPENAI_COMPATIBLE" then Providers::OpenAICompatible.new
        else                         Providers::LocalMiniLM.new
        end
      end
    end
  end
end
