require "test_helper"

class Stray::Embeddings::DownloaderTest < ActiveSupport::TestCase
  test "downloads and writes model file to storage" do
    model_path = Rails.root.join("storage/embeddings/test_download.onnx")
    FileUtils.rm_f(model_path)

    downloader = Stray::Embeddings::Downloader.new
    VCR.use_cassette("embeddings/downloader_success") do
      downloader.stub(:model_path, model_path) do
        downloader.stub(:url, "https://huggingface.co/test/model.onnx") do
          downloader.download
        end
      end
    end

    assert File.exist?(model_path)
    assert_equal "fake model bytes", File.read(model_path)
  ensure
    FileUtils.rm_f(model_path)
  end

  test "raises on network failure" do
    downloader = Stray::Embeddings::Downloader.new
    VCR.use_cassette("embeddings/downloader_failure") do
      downloader.stub(:url, "https://huggingface.co/test/fail.onnx") do
        assert_raises(Stray::Embeddings::DownloadError) do
          downloader.download
        end
      end
    end
  end
end
