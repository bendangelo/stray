require "onnxruntime"

module Embeddings
  module Providers
    class LocalMiniLM
      def initialize(model_path:, vocab_path:)
        @model_path = model_path
        @vocab_path = vocab_path
      end

      def embed(text)
        raise ModelMissing.new unless model_present?

        session = OnnxRuntime.load(@model_path)
        input_ids = tokenizer.encode(Embeddings::Text.normalize(text))
        attention_mask = Array.new(input_ids.length, 1)

        output = session.run({
          "input_ids" => [ input_ids ],
          "attention_mask" => [ attention_mask ]
        })

        extract_embedding(output)
      end

      private

      def model_present?
        File.exist?(@model_path)
      end

      def tokenizer
        @tokenizer ||= Tokenizer.new(@vocab_path)
      end

      def extract_embedding(output)
        hidden = output["last_hidden_state"]
        mean_pool(hidden)
      end

      def mean_pool(hidden_state)
        tokens = hidden_state[0]
        sum = Array.new(tokens[0].length, 0.0)
        tokens.each do |token_vec|
          token_vec.each_with_index { |val, i| sum[i] += val }
        end
        sum.map { |v| v / tokens.length.to_f }
      end
    end
  end
end
