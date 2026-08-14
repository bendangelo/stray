require "uri"

module Stray
  module Youtube
    class ChannelResolver
      Result = Data.define(:channel_id, :rss_url, :channel_name, :channel_url)

      RSS_BASE = "https://www.youtube.com/feeds/videos.xml?channel_id="

      class << self
        def resolve(url)
          uri = URI.parse(url)
          raise ArgumentError, "Not a YouTube URL" unless youtube?(uri)
          raise ArgumentError, "Not a channel URL" if video_url?(uri)

          channel_id = extract_channel_id(uri)
          raise ArgumentError, "Could not extract channel ID from URL" unless channel_id

          Result.new(
            channel_id:,
            rss_url: "#{RSS_BASE}#{channel_id}",
            channel_name: nil,
            channel_url: uri.to_s
          )
        end

        def build_rss_url(channel_id)
          "#{RSS_BASE}#{channel_id}"
        end

        private

        def youtube?(uri)
          uri.host&.end_with?("youtube.com") || uri.host == "youtu.be"
        end

        def video_url?(uri)
          (uri.host == "youtu.be" && uri.path.present?) ||
            (uri.host&.end_with?("youtube.com") && uri.path == "/watch")
        end

        def extract_channel_id(uri)
          if uri.path&.start_with?("/channel/")
            uri.path.match(%r{/channel/(UC[a-zA-Z0-9_-]+)})&.captures&.first
          end
        end
      end
    end
  end
end
