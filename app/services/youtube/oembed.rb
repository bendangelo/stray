require "uri"
require "json"
require "faraday"

module Youtube
  class Oembed
    Result = Data.define(:title, :author_name, :author_url, :thumbnail_url, :external_id)

    ENDPOINT = "https://www.youtube.com/oembed"

    class << self
      def fetch(video_url)
        uri = URI.parse(video_url)
        raise ArgumentError, "Not a YouTube URL" unless youtube?(uri)

        video_id = extract_video_id(uri)
        raise ArgumentError, "Could not extract video ID" unless video_id

        response = http_client.get(ENDPOINT, { url: "https://www.youtube.com/watch?v=#{video_id}", format: "json" })
        raise Stray::ExtractionError, "oEmbed fetch failed: #{response.status}" unless response.status == 200

        data = JSON.parse(response.body)
        Result.new(
          title: data["title"],
          author_name: data["author_name"],
          author_url: data["author_url"],
          thumbnail_url: data["thumbnail_url"],
          external_id: video_id
        )
      rescue JSON::ParserError => e
        raise Stray::ExtractionError, "oEmbed returned invalid JSON: #{e.message}"
      end

      def http_client
        Faraday.new do |conn|
          conn.response :follow_redirects
          conn.options.timeout = 30
          conn.options.open_timeout = 10
          conn.adapter :net_http
        end
      end

      private

      def youtube?(uri)
        uri.host&.end_with?("youtube.com") || uri.host == "youtu.be"
      end

      def extract_video_id(uri)
        if uri.host == "youtu.be"
          uri.path.sub(%r{^/}, "")
        elsif uri.host&.end_with?("youtube.com") && uri.path == "/watch"
          Rack::Utils.parse_query(uri.query.to_s)["v"]
        end
      end
    end
  end
end
