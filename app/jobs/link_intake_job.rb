class LinkIntakeJob < ApplicationJob
  queue_as :default

  retry_on Stray::YtDlp::Error, wait: 1.minute, attempts: 2

  discard_on Stray::YtDlp::Error do |job, error|
    user_id = job.arguments.first
    url = job.arguments.second
    job.send(:broadcast_error, user_id, "Could not add #{url}: #{error.message}")
  end

  def perform(user_id, url)
    @user_id = user_id
    @url = url

    content, source = extract_and_create

    broadcast_success(source, content)
  end

  private

  def extract_and_create
    if youtube_channel_url?
      resolve_youtube_channel
    elsif youtube_video_url?
      extract_youtube_video
    else
      extract_generic_video
    end
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
    [ [ content ], source ]
  end

  def extract_generic_video
    extractor = Stray::ExtractorRegistry.find_for(@url)
    content = extractor.extract(@url)

    creator = content.creator_identity
    raise Stray::YtDlp::ExtractionFailed, "No channel info in video metadata" unless creator&.external_id

    source = create_source(
      kind: :video_channel,
      url: creator.url,
      external_id: creator.external_id,
      name: creator.name,
      channel_url: creator.url
    )

    create_items(source, [ content ])
    [ [ content ], source ]
  end

  def create_source(kind:, url:, external_id:, name:, channel_url:)
    source = Source.find_or_create_by!(
      user_id: @user_id,
      external_id: external_id,
      kind: kind
    ) do |s|
      s.url = url
      s.name = name
      s.icon_url = nil
      s.next_crawl_at = 1.hour.from_now
    end

    source.update!(url: url, name: name)

    Follow.find_or_create_by!(user_id: @user_id, source_id: source.id)
    source
  end

  def create_items(source, contents)
    return if contents.empty?

    rows = contents.map do |content|
      {
        source_id: source.id,
        user_id: @user_id,
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

    Item.upsert_all(rows, unique_by: [ :source_id, :external_id ], returning: :id).then do |result|
      item_ids = result.to_a.map { |row| row["id"] }

      contents.each_with_index do |content, i|
        item_id = item_ids[i]
        apply_extractor_tags(source, item_id, content)
        EmbeddingJob.perform_later("Item", item_id)
      end
    end
  end

  def apply_extractor_tags(source, item_id, content)
    return unless content.tags&.any?

    item = Item.find(item_id)
    content.tags.each do |name|
      tag = Tag.find_or_create_by!(user_id: @user_id, name: name)
      Tagging.find_or_create_by!(item: item, tag: tag, source: :user)
      EmbeddingJob.perform_later("Tag", tag.id) if tag.embedding.nil?
    end
  end

  def broadcast_success(source, contents)
    count = Array(contents).size
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_#{@user_id}_intake",
      target: "intake_status",
      html: "<div id=\"intake_status\" class=\"rounded-lg border p-4\">\n" \
            "  <p class=\"font-semibold\">Following #{ERB::Util.html_escape(source.display_name)}</p>\n" \
            "  <p class=\"text-sm text-gray-500\">#{count} new video#{'s' if count != 1}</p>\n" \
            "</div>"
    )
  end

  def broadcast_error(user_id, message)
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_#{user_id}_intake",
      target: "intake_status",
      html: "<div id=\"intake_status\" class=\"rounded-lg border border-red-500 p-4\">\n" \
            "  <p class=\"text-red-700\">#{ERB::Util.html_escape(message)}</p>\n" \
            "</div>"
    )
  end
end
