class LinkIntakeJob < ApplicationJob
  queue_as :default

  NO_MISSING_METADATA_UPDATE = %i[title url content_text content_html fetched_at].freeze

  retry_on Stray::YtDlp::Error, wait: 1.minute, attempts: 2
  retry_on Stray::ExtractionError, wait: 1.minute, attempts: 3

  discard_on Stray::YtDlp::Error do |job, error|
    source_id = job.arguments.third
    next unless source_id

    source = Source.find_by(id: source_id)
    next unless source

    source.update!(last_error: error.message, last_error_at: Time.current, status: :failed)
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_#{source.user_id}_sources",
      target: ActionView::RecordIdentifier.dom_id(source),
      partial: "sources/source",
      locals: { source: source }
    )
  end

  discard_on Stray::ExtractionError do |job, error|
    source_id = job.arguments.third
    next unless source_id

    source = Source.find_by(id: source_id)
    next unless source

    source.update!(last_error: error.message, last_error_at: Time.current, status: :failed, next_crawl_at: 5.minutes.from_now)
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_#{source.user_id}_sources",
      target: ActionView::RecordIdentifier.dom_id(source),
      partial: "sources/source",
      locals: { source: source }
    )
  end

  def perform(user_id, url, source_id = nil)
    @user = User.find(user_id)
    @url = url
    @source = source_id && Source.find_by(id: source_id, user_id: user_id)

    extract_and_create
  end

  private

  def extract_and_create
    if @source
      extract_for_existing_source
    else
      case UrlClassifier.classify(@url)&.category
      when :youtube_channel then resolve_youtube_channel
      when :youtube_video   then extract_youtube_video
      when :rss_feed        then create_rss_source
      when :video_channel   then extract_video
      when :rumble_channel_feed then extract_channel_feed(:rumble_channel)
      when :rumble_video        then extract_site_video(:rumble_channel)
      when :bitchute_channel_feed then extract_channel_feed(:bitchute_channel)
      when :bitchute_video        then extract_site_video(:bitchute_channel)
      when :odysee_channel        then extract_channel_feed(:odysee_channel)
      when :peertube_channel_feed then extract_channel_feed(:peertube_channel)
      when :peertube_video        then extract_site_video(:peertube_channel)
      when :generic_page    then extract_generic_page
      else
        raise Stray::ExtractionError, "Unsupported URL: #{@url}"
      end
    end
  end

  def extract_for_existing_source
    @source = Youtube::PendingChannelResolver.call(@source)
    enqueue_full_poll(@source)
    extractor = ExtractorRegistry.find_for_source(@source)
    contents = Array(extractor.extract_feed(@source.url))
    create_items(@source, contents)
  rescue Stray::YtDlp::Error, Stray::ExtractionError
    raise
  rescue StandardError => e
    @source.update!(last_error: e.message, last_error_at: Time.current, status: :failed, next_crawl_at: 5.minutes.from_now)
    broadcast_source_update(@source)
  end

  def resolve_youtube_channel
    result = Youtube::ChannelResolver.resolve(@url)
    extractor = ExtractorRegistry.find_for(result.rss_url)
    contents = Array(extractor.extract(result.rss_url))

    name = result.channel_name
    if name.nil?
      creator = contents.map(&:creator_identity).compact.find { |c| c.name }
      name = creator&.name
    end

    source = create_source(
      kind: :youtube_channel,
      url: result.rss_url,
      external_id: result.channel_id,
      name: name,
      channel_url: result.channel_url
    )

    create_items(source, contents)
    enqueue_full_poll(source)
    [ contents, source ]
  end

  def extract_youtube_video
    oembed = fetch_oembed
    if oembed&.author_url
      extract_youtube_video_via_oembed(oembed)
    else
      extract_youtube_video_via_ytdlp
    end
  end

  def fetch_oembed
    Youtube::Oembed.fetch(@url)
  rescue Stray::ExtractionError, ArgumentError
    nil
  end

  def extract_youtube_video_via_oembed(oembed)
    result = Youtube::ChannelResolver.resolve(oembed.author_url)
    extractor = ExtractorRegistry.find_for(result.rss_url)
    contents = Array(extractor.extract(result.rss_url))

    source = create_source(
      kind: :youtube_channel,
      url: result.rss_url,
      external_id: result.channel_id,
      name: result.channel_name.presence || oembed.author_name,
      channel_url: result.channel_url
    )

    create_items(source, contents)
    enqueue_full_poll(source)
    [ contents, source ]
  end

  def extract_youtube_video_via_ytdlp
    content = Extractors::YtDlp.new.extract(@url)

    creator = content.creator_identity
    raise Stray::YtDlp::ExtractionFailed, "No channel info in video metadata" unless creator&.external_id

    rss_url = Youtube::ChannelResolver.build_rss_url(creator.external_id)

    source = create_source(
      kind: :youtube_channel,
      url: rss_url,
      external_id: creator.external_id,
      name: creator.name,
      channel_url: creator.url
    )

    create_items(source, [ content ])
    enqueue_full_poll(source)
    [ [ content ], source ]
  end

  def create_rss_source
    extractor = ExtractorRegistry.find_for(@url)
    contents = Array(extractor.extract_feed(@url))

    creator = contents.map(&:creator_identity).compact.find { |c| c.name }
    source = create_source(
      kind: :rss_feed,
      url: @url,
      external_id: Digest::SHA256.hexdigest(@url)[0, 16],
      name: creator&.name
    )

    create_items(source, contents)
    enqueue_full_poll(source)
    [ contents, source ]
  end

  def extract_video
    extractor = ExtractorRegistry.find_for(@url)
    content = extractor.extract(@url)

    creator = content.creator_identity
    if creator&.external_id
      create_video_source(content, creator)
    else
      create_generic_page_source(content)
    end
  end

  def extract_channel_feed(kind)
    extractor = ExtractorRegistry.find_for(@url)
    contents = Array(extractor.extract_feed(@url))

    creator = contents.map(&:creator_identity).compact.find { |c| c.external_id }
    source = create_source(
      kind: kind,
      url: @url,
      external_id: creator&.external_id || Digest::SHA256.hexdigest(@url)[0, 16],
      name: creator&.name,
      channel_url: @url
    )

    create_items(source, contents)
    enqueue_full_poll(source)
    [ contents, source ]
  end

  def extract_site_video(kind)
    extractor = ExtractorRegistry.find_for(@url)
    content = extractor.extract(@url)

    creator = content.creator_identity
    if creator&.external_id
      source = create_source(
        kind: kind,
        url: creator.url || @url,
        external_id: creator.external_id,
        name: creator.name,
        channel_url: creator.url
      )
      create_items(source, [ content ])
      enqueue_full_poll(source)
      [ [ content ], source ]
    else
      create_generic_page_source(content)
    end
  end

  def extract_generic_page
    extractor = ExtractorRegistry.find_for(@url)
    content = extractor.extract(@url)
    create_generic_page_source(content)
  end

  def create_video_source(content, creator)
    source = create_source(
      kind: :video_channel,
      url: creator.url,
      external_id: creator.external_id,
      name: creator.name,
      channel_url: creator.url
    )

    create_items(source, [ content ])
    enqueue_full_poll(source)
    [ [ content ], source ]
  end

  def create_generic_page_source(content)
    source = create_source(
      kind: :generic_page,
      url: content.url,
      external_id: content.external_id,
      name: extract_page_name(content)
    )

    create_items(source, [ content ])
    enqueue_full_poll(source)
    [ [ content ], source ]
  end

  def extract_page_name(content)
    content.title.presence || begin
      uri = URI.parse(content.url)
      uri.host&.sub(/^www\./, "")
    rescue URI::InvalidURIError
      nil
    end
  end

  def create_source(kind:, url:, external_id:, name:, channel_url: nil)
    return @source if @source

    Source.follow!(@user, kind: kind, url: url, external_id: external_id, name: name, channel_url: channel_url)
  end

  def enqueue_full_poll(source)
    SourcePollJob.set(wait: 10.seconds).perform_later(source.id)
  end

  def broadcast_source_update(source)
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_#{source.user_id}_sources",
      target: ActionView::RecordIdentifier.dom_id(source),
      partial: "sources/source",
      locals: { source: source }
    )
  end

  def create_items(source, contents)
    return if contents.empty?

    complete, incomplete = contents.partition { |c| c.duration.present? && c.thumbnail_url.present? && c.published_at.present? }

    id_by_external_id = {}
    id_by_external_id.merge!(upsert_rows(source, complete)) if complete.any?
    id_by_external_id.merge!(upsert_rows(source, incomplete, update_only: NO_MISSING_METADATA_UPDATE)) if incomplete.any?

    needs_enrichment_ids = []
    contents.each do |content|
      item_id = id_by_external_id[content.external_id]
      apply_extractor_tags(source, item_id, content)
      EmbeddingJob.perform_later("Item", item_id)
      needs_enrichment_ids << item_id if content.duration.blank? || content.thumbnail_url.blank? || content.published_at.blank?
    end

    MetadataEnrichmentJob.perform_later(source.id, needs_enrichment_ids) if needs_enrichment_ids.any?
  end

  def upsert_rows(source, batch, update_only: nil)
    rows = batch.map do |content|
      {
        source_id: source.id,
        user_id: @user.id,
        external_id: content.external_id,
        title: content.title,
        url: content.url,
        content_text: content.content_text,
        content_html: content.content_html,
        thumbnail_url: content.thumbnail_url,
        duration: content.duration,
        published_at: content.published_at,
        fetched_at: Time.current,
        state: 0,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    opts = { unique_by: [ :source_id, :external_id ], returning: [ :id, :external_id ] }
    opts[:update_only] = update_only if update_only
    Item.upsert_all(rows, **opts).to_a.each_with_object({}) { |row, h| h[row["external_id"]] = row["id"] }
  end

  def apply_extractor_tags(source, item_id, content)
    return unless content.tags&.any?

    item = Item.find(item_id)
    content.tags.each do |name|
      tag = Tag.find_or_create_by!(user_id: @user.id, name: name)
      Tagging.find_or_create_by!(item: item, tag: tag, source: :user)
      EmbeddingJob.perform_later("Tag", tag.id) if tag.embedding.nil?
    end
  end
end
