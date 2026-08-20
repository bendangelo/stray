class UrlClassifier
  Classification = Data.define(:category, :source_kind, :extractor_class, :resolver)

  VIDEO_HOSTS = %w[bitchute.com].freeze

  class << self
    def classify(url)
      uri = URI.parse(url)
      return nil unless uri.scheme.in?(%w[http https]) && uri.host.present?

      if stray_collection?(uri)
        classification(:stray_collection, "stray_collection", Extractors::RemoteCollection)
      elsif youtube_channel?(uri)
        classification(:youtube_channel, "youtube_channel", Extractors::YoutubeRss, Youtube::ChannelResolver)
      elsif youtube_video?(uri)
        classification(:youtube_video, "youtube_channel", nil, Youtube::ChannelResolver)
      elsif rss_feed?(uri)
        classification(:rss_feed, "rss_feed", Extractors::RssAtom)
      elsif video_host?(uri)
        classification(:video_channel, "video_channel", Extractors::YtDlp)
      else
        classification(:generic_page, "generic_page", Extractors::GenericPage)
      end
    rescue URI::InvalidURIError
      nil
    end

    private

    def classification(category, source_kind, extractor_class, resolver = nil)
      Classification.new(category: category, source_kind: source_kind, extractor_class: extractor_class, resolver: resolver)
    end

    def stray_collection?(uri)
      Extractors::RemoteCollection.matches?(uri.to_s) ||
        uri.path&.match?(%r{^/c/[A-Za-z0-9]{24}$})
    end

    def youtube_channel?(uri)
      host = uri.host
      return false unless host&.end_with?("youtube.com") || host == "youtu.be"

      path = uri.path.to_s
      if host&.end_with?("youtube.com")
        path.match?(%r{^/(channel/UC|@|c/|user/)}) || path == "/feeds/videos.xml"
      else
        path.match?(%r{^/(@|channel/)})
      end
    end

    def youtube_video?(uri)
      host = uri.host
      path = uri.path.to_s
      (host == "youtu.be" && path.present? && !path.start_with?("/@", "/channel/")) ||
        (host&.end_with?("youtube.com") && path == "/watch")
    end

    def rss_feed?(uri)
      Extractors::RssAtom.matches?(uri.to_s)
    end

    def video_host?(uri)
      VIDEO_HOSTS.any? { |h| uri.host&.end_with?(h) }
    end
  end
end
