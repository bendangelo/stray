require "test_helper"

class Stray::Embeddings::DownloaderTest < ActiveSupport::TestCase
  test "downloads and writes model file to storage" do
    fake_content = "fake model bytes"
    model_path = Rails.root.join("storage/embeddings/test_download.onnx")
    FileUtils.rm_f(model_path)

    stub_request(:get, "https://huggingface.co/test/model.onnx")
      .to_return(status: 200, body: fake_content)

    downloader = Stray::Embeddings::Downloader.new
    downloader.stub(:model_path, model_path) do
      downloader.stub(:url, "https://huggingface.co/test/model.onnx") do
        downloader.download
      end
    end

    assert File.exist?(model_path)
    assert_equal fake_content, File.read(model_path)
  ensure
    FileUtils.rm_f(model_path)
  end

  test "raises on network failure" do
    stub_request(:get, "https://huggingface.co/test/fail.onnx")
      .to_return(status: 500)

    downloader = Stray::Embeddings::Downloader.new
    downloader.stub(:url, "https://huggingface.co/test/fail.onnx") do
      assert_raises(Stray::Embeddings::DownloadError) do
        downloader.download
      end
    end
  end
end
