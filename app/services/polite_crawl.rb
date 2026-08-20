class PoliteCrawl
  class << self
    def delay_seconds
      (Setting.get(:polite_crawl_delay) || 1.0).to_f
    end

    def sleep
      secs = delay_seconds
      Kernel.sleep(secs) if secs.positive?
    end

    def get(url, http_client:)
      sleep
      http_client.get(url)
    end
  end
end
