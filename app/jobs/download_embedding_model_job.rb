class DownloadEmbeddingModelJob < ApplicationJob
  queue_as :default

  def perform
    Stray::Embeddings::Downloader.new.download
  end
end
