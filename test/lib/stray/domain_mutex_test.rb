require "test_helper"

class Stray::DomainMutexTest < ActiveSupport::TestCase
  def setup
    @cache = ActiveSupport::Cache::MemoryStore.new
  end

  def with_lock(domain, timeout: Stray::DomainMutex::DEFAULT_TIMEOUT, &block)
    Rails.stub(:cache, @cache) do
      Stray::DomainMutex.with_lock(domain, timeout: timeout, &block)
    end
  end

  test "acquires lock and yields block" do
    executed = false
    with_lock("example.com") do
      executed = true
      assert @cache.exist?("stray:domain_lock:example.com")
    end
    assert executed
    assert_not @cache.exist?("stray:domain_lock:example.com")
  end

  test "releases lock even on exception" do
    assert_raises(StandardError) do
      with_lock("example.com") do
        raise StandardError, "boom"
      end
    end
    assert_not @cache.exist?("stray:domain_lock:example.com")
  end

  test "raises LockTimeout when lock already held" do
    @cache.write("stray:domain_lock:example.com", Process.pid, expires_in: 5.minutes)

    assert_raises(Stray::DomainMutex::LockTimeout) do
      with_lock("example.com", timeout: 0.seconds) do
        # never reached
      end
    end
  end

  test "extracts domain from URL" do
    assert_equal "example.com", Stray::DomainMutex.domain_for("https://www.example.com/path?q=1")
    assert_equal "bitchute.com", Stray::DomainMutex.domain_for("https://bitchute.com/video/abc")
    assert_nil Stray::DomainMutex.domain_for("not a url")
  end
end
