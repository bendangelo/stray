require "test_helper"

class Embeddings::TextTest < ActiveSupport::TestCase
  test "normalizes simple text" do
    assert_equal "hello world", Embeddings::Text.normalize("hello world")
  end

  test "strips HTML tags" do
    assert_equal "hello world", Embeddings::Text.normalize("<p>hello</p><br>world")
  end

  test "collapses whitespace" do
    assert_equal "hello world", Embeddings::Text.normalize("hello\n\n  world")
  end

  test "truncates long text to approximately 512 words" do
    long = ("word " * 1000).strip
    result = Embeddings::Text.normalize(long)
    word_count = result.split.length
    assert word_count <= 515
  end

  test "returns empty string for nil" do
    assert_equal "", Embeddings::Text.normalize(nil)
  end
end
