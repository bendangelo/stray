class Source
  class StatusMachine
    BACKOFF_MINUTES = [ 1, 2, 5, 15, 30, 60 ].freeze
    HARD_FAIL_NEXT_CRAWL = 5.minutes

    class << self
      def mark_ok!(source, etag: nil, last_modified: nil)
        source.update!(
          status: :ok,
          last_polled_at: Time.current,
          last_error: nil,
          last_error_at: nil,
          recovery_attempts: 0,
          etag: etag || source.etag,
          last_modified: last_modified || source.last_modified
        )
        source
      end

      def mark_degraded!(source)
        source.update!(
          status: :degraded,
          last_polled_at: Time.current,
          last_error: nil,
          last_error_at: nil,
          recovery_attempts: 0
        )
        source
      end

      # Transient error: auto-retry with exponential backoff.
      def mark_recovering!(source, message:)
        attempts = source.recovery_attempts + 1
        delay = BACKOFF_MINUTES.fetch(attempts - 1, BACKOFF_MINUTES.last).minutes
        source.update!(
          status: :recovering,
          last_error: message,
          last_error_at: Time.current,
          recovery_attempts: attempts,
          next_crawl_at: Time.current + delay,
          polling: false
        )
        source
      end

      # Hard error: requires manual pull to retry.
      def mark_failed!(source, message:)
        source.update!(
          status: :failed,
          last_error: message,
          last_error_at: Time.current,
          next_crawl_at: Time.current + HARD_FAIL_NEXT_CRAWL,
          polling: false
        )
        source
      end

      # Called by controller `pull` action and by create actions.
      def reset_for_poll!(source)
        source.update!(
          status: :pending,
          last_error: nil,
          last_error_at: nil,
          polling: true,
          next_crawl_at: nil
        )
        source
      end

      # Called by the sweep for sources abandoned in :pending.
      def recover_abandoned!(source, message:)
        mark_recovering!(source, message: message)
      end
    end
  end
end
