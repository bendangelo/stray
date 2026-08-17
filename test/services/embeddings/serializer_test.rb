require "test_helper"

class Embeddings::SerializerTest < ActiveSupport::TestCase
  test "pack and unpack round-trips an array of floats" do
    original = [ 0.1, 0.2, 0.3, -0.4, 0.5 ]
    blob = Embeddings::Serializer.pack(original)
    result = Embeddings::Serializer.unpack(blob)

    assert_equal original.length, result.length
    original.each_with_index do |val, i|
      assert_in_delta val, result[i], 0.0001
    end
  end

  test "pack produces a binary string" do
    blob = Embeddings::Serializer.pack([ 1.0, 2.0 ])
    assert_equal Encoding::BINARY, blob.encoding
  end

  test "unpack of empty blob returns empty array" do
    assert_equal [], Embeddings::Serializer.unpack("")
  end
end
