require "open3"
require "json"
require "timeout"

require_relative "error"

module Stray
  module YtDlp
    class Runner
      attr_reader :binary, :timeout

      def initialize(binary: "yt-dlp", timeout: 30)
        @binary = binary
        @timeout = timeout
      end

      def single_video(url)
        stdout, stderr, status = run_command("--dump-json", url)
        raise ExtractionFailed, failure_message(status, stderr) unless status.success?

        parse_json(stdout)
      rescue Errno::ENOENT
        raise Error, "yt-dlp binary not found: #{binary}"
      end

      def channel_listings(url, limit: nil, timeout: 120)
        args = [ "--flat-playlist", "--dump-json" ]
        args += [ "--playlist-end", limit.to_s ] if limit
        args << url
        stdout, stderr, status = run_command(*args, timeout: timeout)
        raise ExtractionFailed, failure_message(status, stderr) unless status.success?

        stdout.lines.map { |line| parse_json(line) }
      end

      def channel_metadata(url, timeout: 60)
        stdout, stderr, status = run_command(
          "--flat-playlist", "--dump-json", "--playlist-items", "1", url, timeout: timeout
        )
        raise ExtractionFailed, failure_message(status, stderr) unless status.success?

        line = stdout.lines.first
        return nil if line.nil? || line.strip.empty?

        parse_json(line)
      rescue Errno::ENOENT
        raise Error, "yt-dlp binary not found: #{binary}"
      end

      private

      def run_command(*args, timeout: @timeout)
        execute(binary, *args, timeout: timeout)
      rescue ::Timeout::Error
        raise Stray::YtDlp::Timeout, "yt-dlp timed out after #{timeout}s"
      end

      def execute(*cmd, timeout:)
        Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          pid = wait_thr.pid

          out_thread = Thread.new { stdout.read }
          err_thread = Thread.new { stderr.read }

          timed_out = false
          watcher = Thread.new do
            sleep(timeout)
            timed_out = true
            Process.kill("TERM", pid) rescue nil
          end

          status = wait_thr.value
          watcher.kill
          watcher.join
          out_thread.join
          err_thread.join

          raise ::Timeout::Error, "yt-dlp timed out after #{timeout}s" if timed_out
          [ out_thread.value, err_thread.value, status ]
        end
      end

      def failure_message(status, stderr)
        detail = stderr.to_s.strip
        detail = "yt-dlp exited with non-zero status" if detail.empty?
        detail
      end

      def parse_json(text)
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise ExtractionFailed, "yt-dlp returned invalid JSON: #{e.message}"
      end
    end
  end
end
