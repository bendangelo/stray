require "faraday"
require "digest"

module Embeddings
  class Downloader
    def download
      FileUtils.mkdir_p(File.dirname(model_path))
      response = http_client.get(url)
      raise DownloadError, "HTTP #{response.status}" unless response.status == 200

      File.binwrite(model_path, response.body)
      verify_checksum!
      mark_present!
      model_path
    end

    private

    def model_path
      Rails.root.join("storage/embeddings/all-MiniLM-L6-v2.onnx")
    end

    def url
      yaml_config.dig(Rails.env.to_s, "embedding_model_url")
    end

    def expected_sha256
      yaml_config.dig(Rails.env.to_s, "embedding_model_sha256")
    end

    def yaml_config
      path = Rails.root.join("config/stray.yml")
      @yaml_config ||= File.exist?(path) ? YAML.safe_load(File.read(path), aliases: true) : {}
    end

    def http_client
      Faraday.new do |conn|
        conn.response :follow_redirects
        conn.adapter :net_http
      end
    end

    def verify_checksum!
      return if expected_sha256.blank? || expected_sha256 == "PLACEHOLDER_FILL_AFTER_FIRST_DOWNLOAD"

      actual = Digest::SHA256.file(model_path).hexdigest
      raise DownloadError, "Checksum mismatch" unless actual == expected_sha256
    end

    def mark_present!
      Setting.current.update!(embedding_model_present: true)
    end
  end
end
