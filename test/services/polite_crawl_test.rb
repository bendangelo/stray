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
end
