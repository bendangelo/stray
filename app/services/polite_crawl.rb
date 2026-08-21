module Stray
  class RateBudgetExhausted < StandardError; end
end

class PoliteCrawl
  RATE_BUDGET_PER_MINUTE = 6
  RATE_BUDGET_INTERVAL = 60.0 / RATE_BUDGET_PER_MINUTE

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
      check_rate_budget(url)
      sleep
      http_client.get(url)
    end

    def get_with_cache(url, http_client:, etag: nil, last_modified: nil)
      raise UrlGuard::Blocked, "URL blocked by UrlGuard" unless UrlGuard.allowed?(url)
      check_rate_budget(url)
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

    private

    def check_rate_budget(url)
      domain = DomainMutex.domain_for(url)
      return unless domain

      key = "stray:rate:#{domain}"
      last = Rails.cache.read(key)
      now = Time.current.to_f
      if last && (now - last) < RATE_BUDGET_INTERVAL
        raise Stray::RateBudgetExhausted, "Rate budget exhausted for #{domain}"
      end
      Rails.cache.write(key, now, expires_in: 1.hour)
    end
  end
end
