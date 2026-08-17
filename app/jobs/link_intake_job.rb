class LinkIntakeJob < ApplicationJob
  queue_as :default

  NO_DURATION_UPDATE = %i[title url content_text content_html thumbnail_url published_at fetched_at].freeze

  retry_on Stray::YtDlp::Error, wait: 1.minute, attempts: 2

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
    elsif youtube_channel_url?
      resolve_youtube_channel
    elsif youtube_video_url?
      extract_youtube_video
    else
      extract_generic
    end
  end

  def extract_for_existing_source
    resolve_pending_youtube_channel if pending_youtube_channel?
    extractor = Stray::ExtractorRegistry.find_for_source(@source)
    contents = Array(extractor.extract_feed(@source.url))
    create_items(@source, contents)
    enqueue_full_poll(@source)
  end

  def pending_youtube_channel?
    @source.kind == "youtube_channel" &&
      @source.status == "pending" &&
      !Stray::Extractors::YoutubeRss.matches?(@source.url)
  end

  def resolve_pending_youtube_channel
    result = Stray::Youtube::ChannelResolver.resolve(@source.url)
    @source.update!(
      url: result.rss_url,
      external_id: result.channel_id,
      name: result.channel_name.presence || @source.name,
      status: :ok
    )
  rescue ActiveRecord::RecordNotUnique
    adopt_existing_channel(result.channel_id)
  rescue StandardError => e
    @source.update!(last_error: e.message, last_error_at: Time.current, status: :failed, next_crawl_at: 5.minutes.from_now)
  end

  def adopt_existing_channel(channel_id)
    existing = Source.find_by(user: @user, kind: :youtube_channel, external_id: channel_id)
    return unless existing

    @source.follows.update_all(source_id: existing.id)
    @source.items.update_all(source_id: existing.id)
    @source.destroy!
    @source = existing
  end

  def youtube_channel_url?
    uri = URI.parse(@url)
    uri.host&.end_with?("youtube.com") &&
      uri.path&.match?(%r{^/(channel/UC|@|c/|user/)})
  rescue URI::InvalidURIError
    false
  end

  def youtube_video_url?
    uri = URI.parse(@url)
    (uri.host == "youtu.be" && uri.path.present?) ||
      (uri.host&.end_with?("youtube.com") && uri.path == "/watch")
  rescue URI::InvalidURIError
    false
  end

  def resolve_youtube_channel
    result = Stray::Youtube::ChannelResolver.resolve(@url)
    extractor = Stray::ExtractorRegistry.find_for(result.rss_url)
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
    extractor = Stray::ExtractorRegistry.find_for(@url)
    content = extractor.extract(@url)

    creator = content.creator_identity
    raise Stray::YtDlp::ExtractionFailed, "No channel info in video metadata" unless creator&.external_id

    rss_url = Stray::Youtube::ChannelResolver.build_rss_url(creator.external_id)

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

  def extract_generic
    extractor = Stray::ExtractorRegistry.find_for(@url)
    content = extractor.extract(@url)

    creator = content.creator_identity
    if creator&.external_id
      create_video_source(content, creator)
    else
      create_generic_page_source(content)
    end
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

    Source.follow!(@user, kind: kind, url: url, external_id: external_id, name: name)
  end

  def enqueue_full_poll(source)
    SourcePollJob.set(wait: 10.seconds).perform_later(source.id)
  end

  def create_items(source, contents)
    return if contents.empty?

    with_duration, without_duration = contents.partition { |c| c.duration.present? }

    id_by_external_id = {}
    id_by_external_id.merge!(upsert_rows(source, with_duration)) if with_duration.any?
    id_by_external_id.merge!(upsert_rows(source, without_duration, update_only: NO_DURATION_UPDATE)) if without_duration.any?

    missing_duration_ids = []
    contents.each do |content|
      item_id = id_by_external_id[content.external_id]
      apply_extractor_tags(source, item_id, content)
      EmbeddingJob.perform_later("Item", item_id)
      missing_duration_ids << item_id if content.duration.blank?
    end

    DurationEnrichmentJob.perform_later(source.id, missing_duration_ids) if missing_duration_ids.any?
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
