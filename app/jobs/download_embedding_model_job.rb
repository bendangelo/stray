class DownloadEmbeddingModelJob < ApplicationJob
  queue_as :default

  def perform
    Embeddings::Downloader.new.download
  end
end
