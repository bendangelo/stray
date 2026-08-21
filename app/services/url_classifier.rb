class UrlClassifier
  Classification = Data.define(:category, :source_kind, :extractor_class, :resolver)

  class << self
    def classify(url)
      uri = URI.parse(url)
      return nil unless uri.scheme.in?(%w[http https]) && uri.host.present?

      if stray_collection?(uri)
        classification(:stray_collection, "stray_collection", Bridges::RemoteCollection)
      elsif youtube_channel?(uri)
        classification(:youtube_channel, "youtube_channel", Bridges::YoutubeRss, Youtube::ChannelResolver)
      elsif youtube_video?(uri)
        classification(:youtube_video, "youtube_channel", nil, Youtube::ChannelResolver)
      elsif rss_feed?(uri)
        classification(:rss_feed, "rss_feed", Bridges::RssAtom)
      elsif rumble?(uri)
        classification(rumble_channel?(uri) ? :rumble_channel_feed : :rumble_video,
                      "rumble_channel", Bridges::Rumble)
      elsif bitchute?(uri)
        classification(bitchute_channel?(uri) ? :bitchute_channel_feed : :bitchute_video,
                      "bitchute_channel", Bridges::Bitchute)
      elsif odysee_channel?(uri)
        classification(:odysee_channel, "odysee_channel", Bridges::Odysee)
      elsif peertube?(uri)
        classification(peertube_channel?(uri) ? :peertube_channel_feed : :peertube_video,
                      "peertube_channel", Bridges::Peertube)
      else
        classification(:generic_page, "generic_page", Bridges::GenericPage)
      end
    rescue URI::InvalidURIError
      nil
    end

    private

    def classification(category, source_kind, extractor_class, resolver = nil)
      Classification.new(category: category, source_kind: source_kind, extractor_class: extractor_class, resolver: resolver)
    end

    def stray_collection?(uri)
      Bridges::RemoteCollection.matches?(uri.to_s) ||
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
      Bridges::RssAtom.matches?(uri.to_s)
    end

    def rumble?(uri)
      uri.host&.end_with?("rumble.com")
    end

    def rumble_channel?(uri)
      uri.path.to_s.match?(%r{^/(c|user)/})
    end

    def bitchute?(uri)
      uri.host&.end_with?("bitchute.com")
    end

    def bitchute_channel?(uri)
      uri.path.to_s.match?(%r{^/channel/})
    end

    def odysee_channel?(uri)
      uri.host&.end_with?("odysee.com") && uri.path.to_s.match?(%r{^/@})
    end

    def peertube?(uri)
      uri.host.present? && uri.path.to_s.match?(%r{/video-channels/|/c/|/w/})
    end

    def peertube_channel?(uri)
      uri.path.to_s.match?(%r{/(video-channels|c)/})
    end
  end
end
