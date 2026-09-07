class PromoteSavedVideoJob < ApplicationJob
  queue_as :default

  retry_on Stray::YtDlp::Error, wait: 1.minute, attempts: 2
  retry_on Stray::ExtractionError, wait: 1.minute, attempts: 3

  def perform(item_id)
    item = Item.find_by(id: item_id)
    return unless item

    channel_source = resolve_and_create_channel_source(item)
    return unless channel_source

    saved_source = item.source
    item.update!(source_id: channel_source.id)
    saved_source.destroy

    SourcePollJob.set(wait: 10.seconds).perform_later(channel_source.id)
  end

  private

  def resolve_and_create_channel_source(item)
    classification = UrlClassifier.classify(item.url)&.category

    case classification
    when :youtube_video
      resolve_youtube_channel(item.user, item.url)
    when :rumble_video, :bitchute_video, :odysee_video, :peertube_video
      resolve_site_channel(item.user, item.url, classification)
    when :video_channel
      resolve_generic_video_channel(item.user, item.url)
    end
  end

  def resolve_youtube_channel(user, url)
    oembed = fetch_oembed(url)
    author_url = oembed&.author_url || url

    result = Youtube::ChannelResolver.resolve(author_url)
    Source.follow!(
      user,
      kind: :youtube_channel,
      url: result.rss_url,
      external_id: result.channel_id,
      name: result.channel_name.presence || oembed&.author_name,
      channel_url: result.channel_url
    )
  end

  def resolve_site_channel(user, url, classification)
    extractor = Stray::BridgeRegistry.find_for(url)
    content = extractor.extract(url)
    creator = content.creator_identity
    raise Stray::ExtractionError, "No channel info in video metadata" unless creator&.external_id

    kind = classification.to_s.sub("_video", "_channel").to_sym
    Source.follow!(
      user,
      kind: kind,
      url: creator.url || url,
      external_id: creator.external_id,
      name: creator.name,
      channel_url: creator.url
    )
  end

  def resolve_generic_video_channel(user, url)
    content = Bridges::YtDlp.new.extract(url)
    creator = content.creator_identity
    raise Stray::YtDlp::ExtractionFailed, "No channel info in video metadata" unless creator&.external_id

    Source.follow!(
      user,
      kind: :video_channel,
      url: creator.url || url,
      external_id: creator.external_id,
      name: creator.name,
      channel_url: creator.url
    )
  end

  def fetch_oembed(url)
    Youtube::Oembed.fetch(url)
  rescue Stray::ExtractionError, ArgumentError
    nil
  end
end
