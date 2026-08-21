class PoliteCrawl
  CachedResponse = Data.define(:response, :etag, :last_modified)

  class << self
    def delay_seconds
      (Setting.get(:polite_crawl_delay) || 1.0).to_f
    end

    def sleep
      secs = delay_seconds
      Kernel.sleep(secs) if secs.positive?
    end

    def get(url, http_client:)
      raise UrlGuard::Blocked, "URL blocked by UrlGuard" unless UrlGuard.allowed?(url)
      sleep
      http_client.get(url)
    end

    def get_with_cache(url, http_client:, etag: nil, last_modified: nil)
      raise UrlGuard::Blocked, "URL blocked by UrlGuard" unless UrlGuard.allowed?(url)
      sleep
      headers = {}
      headers["If-None-Match"] = etag if etag.present?
      headers["If-Modified-Since"] = last_modified if last_modified.present?

      response = http_client.get(url, { headers: headers }.compact_blank)
      return :not_modified if response.status == 304

      CachedResponse.new(
        response: response,
        etag: response.headers["etag"] || response.headers["ETag"],
        last_modified: response.headers["last-modified"] || response.headers["Last-Modified"]
      )
    end
  end
end
