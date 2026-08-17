module Embeddings
  class Tokenizer
    CLS_TOKEN = "[CLS]"
    SEP_TOKEN = "[SEP]"
    PAD_TOKEN = "[PAD]"
    UNK_TOKEN = "[UNK]"
    MAX_LENGTH = 128

    def initialize(vocab_path = nil)
      @vocab_path = vocab_path
      @vocab = {}
      load_vocab if vocab_path && File.exist?(vocab_path)
    end

    def tokenize(text)
      tokens = []
      words = text.downcase.gsub(/[^a-z0-9\s]/, "").split
      words.each do |word|
        subtokens = wordpiece_split(word)
        tokens.concat(subtokens)
      end
      tokens.first(MAX_LENGTH - 2)
    end

    def encode(text)
      tokens = tokenize(text)
      ids = [ CLS_TOKEN, *tokens, SEP_TOKEN ].map { |t| vocab_id(t) }
      ids << vocab_id(PAD_TOKEN) while ids.length < MAX_LENGTH
      ids.first(MAX_LENGTH)
    end

    private

    def wordpiece_split(word)
      return [ word ] if word.length <= 6

      [ word[0..5], "##" + word[6..] ]
    end

    def vocab_id(token)
      @vocab[token] || @vocab[UNK_TOKEN] || 0
    end

    def load_vocab
      File.readlines(@vocab_path).each_with_index do |line, i|
        token = line.strip
        @vocab[token] = i
      end
    end
  end
end
