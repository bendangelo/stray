require "open3"
require "json"

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

      def channel_listings(url)
        stdout, stderr, status = run_command("--flat-playlist", "--dump-json", url)
        raise ExtractionFailed, failure_message(status, stderr) unless status.success?

        stdout.lines.map { |line| parse_json(line) }
      end

      private

      def run_command(*args)
        Open3.capture3(binary, *args)
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
