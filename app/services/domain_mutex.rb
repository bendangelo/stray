require "uri"

class DomainMutex
    LOCK_PREFIX = "stray:domain_lock:"
    DEFAULT_TIMEOUT = 10.seconds
    LOCK_TTL = 5.minutes

    class LockTimeout < StandardError; end

    class << self
      def with_lock(domain, timeout: DEFAULT_TIMEOUT)
        return yield if domain.nil?

        key = lock_key(domain)
        acquire(key, timeout)
        begin
          yield
        ensure
          release(key)
        end
      end

      def domain_for(url)
        host = URI.parse(url).host
        host&.sub(/\Awww\./, "")
      rescue URI::InvalidURIError
        nil
      end

      private

      def lock_key(domain)
        "#{LOCK_PREFIX}#{domain}"
      end

      def acquire(key, timeout)
        deadline = Time.current + timeout
        loop do
          if Rails.cache.write(key, Process.pid, expires_in: LOCK_TTL, unless_exist: true)
            return
          end
          raise LockTimeout if Time.current >= deadline

          sleep 1
        end
      end

      def release(key)
        owner = Rails.cache.read(key)
        Rails.cache.delete(key) if owner == Process.pid
      end
    end
end
