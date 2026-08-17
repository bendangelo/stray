require "test_helper"

class Embeddings::TokenizerTest < ActiveSupport::TestCase
  test "loads vendored vocab and maps common words to non-UNK ids" do
    tokenizer = Embeddings::Tokenizer.new(vocab_path)
    unk = 0

    %w[hello world the quick brown fox jumps lazy dog].each do |word|
      ids = tokenizer.encode(word)
      assert ids.any? { |id| id != unk },
             "expected #{word.inspect} to contain a non-UNK id, got #{ids.inspect}"
    end
  end

  test "encode pads to max length" do
    tokenizer = Embeddings::Tokenizer.new(vocab_path)

    assert_equal Embeddings::Tokenizer::MAX_LENGTH, tokenizer.encode("a").length
  end

  test "without a vocab file everything maps to UNK id" do
    tokenizer = Embeddings::Tokenizer.new("/nonexistent/vocab.txt")

    assert_equal [ 0 ], tokenizer.encode("hello")[1..-2].uniq
  end

  private

  def vocab_path
    Rails.root.join("app/services/embeddings/vocab.txt")
  end
end
