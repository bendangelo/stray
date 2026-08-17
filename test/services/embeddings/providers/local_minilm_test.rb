require "test_helper"

class Embeddings::Providers::LocalMiniLMTest < ActiveSupport::TestCase
  def vocab_path
    Rails.root.join("app/services/embeddings/vocab.txt")
  end

  def setup
    @provider = Embeddings::Providers::LocalMiniLM.new(
      model_path: "/nonexistent/model.onnx",
      vocab_path: vocab_path
    )
  end

  test "raises ModelMissing when model file absent" do
    assert_raises(Embeddings::ModelMissing) { @provider.embed("hello") }
  end

  test "embed returns array of floats when model loads" do
    fake_session = Object.new
    fake_session.define_singleton_method(:run) do |_inputs|
      { "last_hidden_state" => [ [ [ 0.1, 0.2, 0.3 ] ] ] }
    end

    model_path = Rails.root.join("storage/embeddings/test_model.onnx")
    FileUtils.mkdir_p(File.dirname(model_path))
    FileUtils.touch(model_path)
    provider = Embeddings::Providers::LocalMiniLM.new(model_path: model_path, vocab_path: vocab_path)

    OnnxRuntime.stub(:load, fake_session) do
      result = provider.embed("hello world")
      assert_kind_of Array, result
      assert result.all? { |v| v.is_a?(Float) }
    end
  ensure
    FileUtils.rm_f(model_path)
  end
end
