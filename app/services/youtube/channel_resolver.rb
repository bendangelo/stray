require "uri"
require "faraday"

module Youtube
  class ChannelResolver
      Result = Data.define(:channel_id, :rss_url, :channel_name, :channel_url)

      RSS_BASE = "https://www.youtube.com/feeds/videos.xml?channel_id="
      BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36"

      class << self
        def resolve(url)
          uri = URI.parse(url)
          raise ArgumentError, "Not a YouTube URL" unless youtube?(uri)
          raise ArgumentError, "Not a channel URL" if video_url?(uri)

          if direct_channel_id?(uri)
            resolve_direct(uri)
          else
            resolve_via_html(uri)
          end
        end

        def build_rss_url(channel_id)
          "#{RSS_BASE}#{channel_id}"
        end

        def http_client
          Faraday.new do |conn|
            conn.headers["User-Agent"] = BROWSER_UA
            conn.headers["Accept-Language"] = "en"
            conn.headers["Cookie"] = "CONSENT=YES+cb"
            conn.response :follow_redirects
            conn.adapter :net_http
          end
        end

        private

        def youtube?(uri)
          uri.host&.end_with?("youtube.com") || uri.host == "youtu.be"
        end

        def video_url?(uri)
          (uri.host == "youtu.be" && uri.path.present? && !uri.path.start_with?("/channel/", "/@")) ||
            (uri.host&.end_with?("youtube.com") && uri.path == "/watch")
        end

        def direct_channel_id?(uri)
          uri.path&.start_with?("/channel/UC")
        end

        def resolve_direct(uri)
          channel_id = uri.path.match(%r{/channel/(UC[a-zA-Z0-9_-]+)})&.captures&.first
          raise ArgumentError, "Could not extract channel ID from URL" unless channel_id

          Result.new(
            channel_id:,
            rss_url: build_rss_url(channel_id),
            channel_name: nil,
            channel_url: uri.to_s
          )
        end

        def resolve_via_html(uri)
          response = http_client.get(uri.to_s)
          body = response.body.to_s

          channel_id = extract_channel_id(body)
          raise ArgumentError, "No channel_id in channel page HTML" unless channel_id

          Result.new(
            channel_id:,
            rss_url: build_rss_url(channel_id),
            channel_name: extract_channel_name(body),
            channel_url: uri.to_s
          )
        rescue ArgumentError
          resolve_via_ytdlp(uri)
        end

        def resolve_via_ytdlp(uri)
          data = Stray::YtDlp::Runner.new.channel_metadata(uri.to_s)

          channel_id = data&.dig("channel_id")
          raise ArgumentError, "yt-dlp did not return a channel_id" unless channel_id

          Result.new(
            channel_id:,
            rss_url: build_rss_url(channel_id),
            channel_name: data["channel"],
            channel_url: data["channel_url"] || uri.to_s
          )
        rescue Errno::ENOENT
          raise ArgumentError, "No channel_id in channel page HTML"
        end

        def extract_channel_id(body)
          body[/"externalChannelId":"(UC[\w-]{22})"/, 1] ||
            body[/<meta property="og:url" content="https:\/\/www\.youtube\.com\/channel\/(UC[\w-]{22})"/, 1] ||
            body[/<link rel="canonical" href="https:\/\/www\.youtube\.com\/channel\/(UC[\w-]{22})"/, 1]
        end

        def extract_channel_name(body)
          body[/<meta property="og:title" content="([^"]+)"/, 1]
        end
      end
    end
end
