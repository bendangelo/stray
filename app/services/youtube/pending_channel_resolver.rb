module Youtube
  class PendingChannelResolver
    def self.call(source)
      new(source).call
    end

    def initialize(source)
      @source = source
    end

    def call
      return @source unless resolvable?

      result = Youtube::ChannelResolver.resolve(@source.url)
      @source.update!(
        url: result.rss_url,
        external_id: result.channel_id,
        name: result.channel_name.presence || @source.name,
        channel_url: result.channel_url.presence || @source.channel_url,
        icon_url: @source.icon_url.presence || result.channel_avatar_url,
        status: :ok
      )
      @source
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      adopt_existing_channel(result.channel_id)
    rescue Stray::YtDlp::Error
      raise
    rescue StandardError => e
      @source.update!(last_error: e.message, last_error_at: Time.current, status: :failed, next_crawl_at: 5.minutes.from_now)
      @source
    end

    private

    def resolvable?
      @source.kind == "youtube_channel" && !Bridges::YoutubeRss.matches?(@source.url)
    end

    def adopt_existing_channel(channel_id)
      existing = Source.find_by(user: @source.user, kind: :youtube_channel, external_id: channel_id)
      return @source unless existing

      @source.items.update_all(source_id: existing.id)
      @source.follows.find_each do |follow|
        Follow.find_or_create_by!(user: follow.user, source: existing)
        follow.destroy!
      end
      @source.destroy!
      existing
    end
  end
end
