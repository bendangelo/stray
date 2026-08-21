require "test_helper"

class PoliteCrawlTest < ActiveSupport::TestCase
  test "delay_seconds reads from Setting.get" do
    Setting.stub(:get, 2.5) do
      assert_equal 2.5, PoliteCrawl.delay_seconds
    end
  end

  test "delay_seconds falls back to 1.0 when setting is nil" do
    Setting.stub(:get, nil) do
      assert_equal 1.0, PoliteCrawl.delay_seconds
    end
  end

  test "sleep sleeps for the configured delay" do
    PoliteCrawl.stub(:delay_seconds, 1.5) do
      slept = nil
      Kernel.stub(:sleep, ->(secs) { slept = secs }) do
        PoliteCrawl.sleep
      end
      assert_equal 1.5, slept
    end
  end

  test "sleep is a no-op when delay is zero" do
    PoliteCrawl.stub(:delay_seconds, 0.0) do
      called = false
      Kernel.stub(:sleep, ->(_secs) { called = true }) do
        PoliteCrawl.sleep
      end
      assert_not called
    end
  end

  test "get sleeps then delegates to the http client" do
    client = Minitest::Mock.new
    client.expect(:get, :response, [ "https://example.com" ])

    slept = false
    PoliteCrawl.stub(:sleep, -> { slept = true }) do
      result = PoliteCrawl.get("https://example.com", http_client: client)
      assert_equal :response, result
    end
    assert slept
    client.verify
  end

  test "get_with_cache sends If-None-Match and If-Modified-Since headers when provided" do
    response = Struct.new(:status, :body, :headers).new(200, "content", { "etag" => "etag123", "last-modified" => "Wed, 01 Jan 2025 00:00:00 GMT" })
    client = Minitest::Mock.new
    client.expect(:get, response, [ "https://example.com", { headers: { "If-None-Match" => "etag123", "If-Modified-Since" => "Wed, 01 Jan 2025 00:00:00 GMT" } } ])

    PoliteCrawl.stub(:sleep, -> {}) do
      result = PoliteCrawl.get_with_cache("https://example.com", http_client: client, etag: "etag123", last_modified: "Wed, 01 Jan 2025 00:00:00 GMT")
      assert_equal response, result.response
    end
    client.verify
  end

  test "get_with_cache returns :not_modified when response status is 304" do
    response = Struct.new(:status, :body, :headers).new(304, "", {})
    client = Minitest::Mock.new
    client.expect(:get, response, [ "https://example.com", { headers: { "If-None-Match" => "etag123" } } ])

    PoliteCrawl.stub(:sleep, -> {}) do
      result = PoliteCrawl.get_with_cache("https://example.com", http_client: client, etag: "etag123", last_modified: nil)
      assert_equal :not_modified, result
    end
    client.verify
  end

  test "get_with_cache extracts ETag and Last-Modified from response headers" do
    response = Struct.new(:status, :body, :headers).new(200, "content", { "etag" => "new-etag", "last-modified" => "Thu, 02 Jan 2025 00:00:00 GMT" })
    client = Minitest::Mock.new
    client.expect(:get, response, [ "https://example.com", {} ])

    PoliteCrawl.stub(:sleep, -> {}) do
      result = PoliteCrawl.get_with_cache("https://example.com", http_client: client, etag: nil, last_modified: nil)
      assert_equal response, result.response
      assert_equal "new-etag", result.etag
      assert_equal "Thu, 02 Jan 2025 00:00:00 GMT", result.last_modified
    end
    client.verify
  end

  test "get raises UrlGuard::Blocked for localhost URLs" do
    client = Minitest::Mock.new
    assert_raises(UrlGuard::Blocked) do
      PoliteCrawl.stub(:sleep, -> {}) do
        PoliteCrawl.get("http://localhost:3000/admin", http_client: client)
      end
    end
  end

  test "get_with_cache raises UrlGuard::Blocked for private IP URLs" do
    client = Minitest::Mock.new
    assert_raises(UrlGuard::Blocked) do
      PoliteCrawl.stub(:sleep, -> {}) do
        PoliteCrawl.get_with_cache("http://192.168.1.1/secret", http_client: client)
      end
    end
  end

  test "rate budget blocks request when domain bucket is exhausted" do
    cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stub(:cache, cache) do
      DomainMutex.stub(:domain_for, "example.com") do
        client = Minitest::Mock.new
        client.expect(:get, :response, [ "https://example.com/1" ])

        PoliteCrawl.stub(:sleep, -> {}) do
          PoliteCrawl.get("https://example.com/1", http_client: client)
        end

        assert_raises(Stray::RateBudgetExhausted) do
          PoliteCrawl.stub(:sleep, -> {}) do
            PoliteCrawl.get("https://example.com/2", http_client: client)
          end
        end
      end
    end
  end

  test "rate budget allows requests after refill" do
    cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stub(:cache, cache) do
      DomainMutex.stub(:domain_for, "example.com") do
        client = Minitest::Mock.new
        client.expect(:get, :response, [ "https://example.com/1" ])

        PoliteCrawl.stub(:sleep, -> {}) do
          PoliteCrawl.get("https://example.com/1", http_client: client)
        end

        travel_to 11.seconds.from_now do
          client.expect(:get, :response, [ "https://example.com/2" ])
          PoliteCrawl.stub(:sleep, -> {}) do
            result = PoliteCrawl.get("https://example.com/2", http_client: client)
            assert_equal :response, result
          end
        end
      end
    end
  end
end
