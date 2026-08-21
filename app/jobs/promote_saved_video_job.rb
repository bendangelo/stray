class PromoteSavedVideoJob < ApplicationJob
  queue_as :default

  retry_on Stray::YtDlp::Error, wait: 1.minute, attempts: 2
  retry_on Stray::ExtractionError, wait: 1.minute, attempts: 3

  def perform(item_id)
    item = Item.find_by(id: item_id)
    return unless item

    channel_source = resolve_and_create_channel_source(item)

    saved_source = item.source
    item.update!(source_id: channel_source.id)
    saved_source.destroy

    SourcePollJob.set(wait: 10.seconds).perform_later(channel_source.id)
  end

  private

  def resolve_and_create_channel_source(item)
    oembed = fetch_oembed(item.url)
    if oembed&.author_url
      resolve_via_oembed(item.user, oembed)
    else
      resolve_via_ytdlp(item.user, item.url)
    end
  end

  def fetch_oembed(url)
    Youtube::Oembed.fetch(url)
  rescue Stray::ExtractionError, ArgumentError
    nil
  end

  def resolve_via_oembed(user, oembed)
    result = Youtube::ChannelResolver.resolve(oembed.author_url)
    Source.follow!(
      user,
      kind: :youtube_channel,
      url: result.rss_url,
      external_id: result.channel_id,
      name: result.channel_name.presence || oembed.author_name,
      channel_url: result.channel_url
    )
  end

  def resolve_via_ytdlp(user, url)
    content = Bridges::YtDlp.new.extract(url)
    creator = content.creator_identity
    raise Stray::YtDlp::ExtractionFailed, "No channel info in video metadata" unless creator&.external_id

    rss_url = Youtube::ChannelResolver.build_rss_url(creator.external_id)
    Source.follow!(
      user,
      kind: :youtube_channel,
      url: rss_url,
      external_id: creator.external_id,
      name: creator.name,
      channel_url: creator.url
    )
  end
end
