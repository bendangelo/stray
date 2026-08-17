namespace :stray do
  namespace :embeddings do
    desc "Download the local embedding model (all-MiniLM-L6-v2)"
    task download: :environment do
      puts "Downloading embedding model..."
      path = Embeddings::Downloader.new.download
      puts "Model saved to: #{path}"
    end
  end
end
