require "test_helper"

class DownloadEmbeddingModelJobTest < ActiveJob::TestCase
  test "calls downloader and marks present" do
    downloader = Object.new
    downloader.define_singleton_method(:download) do
      Setting.current.update!(embedding_model_present: true)
      "/fake/path/model.onnx"
    end

    Stray::Embeddings::Downloader.stub(:new, downloader) do
      DownloadEmbeddingModelJob.perform_now
    end

    assert Setting.current.embedding_model_present
  end
end
