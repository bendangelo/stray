require "test_helper"

class Embeddings::CosineTest < ActiveSupport::TestCase
  test "identical vectors return 1.0" do
    vec = [ 1.0, 2.0, 3.0 ]
    assert_in_delta 1.0, Embeddings::Cosine.similarity(vec, vec), 0.0001
  end

  test "orthogonal vectors return 0.0" do
    assert_in_delta 0.0, Embeddings::Cosine.similarity([ 1.0, 0.0 ], [ 0.0, 1.0 ]), 0.0001
  end

  test "opposite vectors return -1.0" do
    assert_in_delta -1.0, Embeddings::Cosine.similarity([ 1.0, 0.0 ], [ -1.0, 0.0 ]), 0.0001
  end

  test "returns nil for empty vectors" do
    assert_nil Embeddings::Cosine.similarity([], [])
  end

  test "returns nil for zero-magnitude vectors" do
    assert_nil Embeddings::Cosine.similarity([ 0.0, 0.0 ], [ 1.0, 1.0 ])
  end
end
