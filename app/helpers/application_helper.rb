module ApplicationHelper
  def time_ago(time)
    return "" if time.nil?

    seconds = Time.current - time
    if seconds < 60
      "just now"
    elsif seconds < 3600
      "#{(seconds / 60).to_i}m ago"
    elsif seconds < 86400
      "#{(seconds / 3600).to_i}h ago"
    elsif seconds < 604800
      "#{(seconds / 86400).to_i}d ago"
    else
      time.strftime("%b %d, %Y")
    end
  end

  def pretty_duration(seconds)
    return "" if seconds.nil? || seconds <= 0

    if seconds >= 3600
      "%d:%02d:%02d" % [ seconds / 3600, (seconds / 60) % 60, seconds % 60 ]
    else
      "%d:%02d" % [ seconds / 60, seconds % 60 ]
    end
  end

  def embed_url(item)
    case item.source.kind
    when "youtube_channel"
      "https://www.youtube.com/embed/#{item.external_id}"
    when "video_channel"
      uri = parse_url(item.url)
      if uri&.host&.include?("bitchute.com")
        "https://www.bitchute.com/embed/#{item.external_id}"
      end
    when "odysee_channel"
      uri = parse_url(item.url)
      "https://odysee.com/$/embed#{uri.path}" if uri&.host&.end_with?("odysee.com")
    when "rumble_channel"
      uri = parse_url(item.url)
      slug = uri&.path.to_s.match(%r{^/(v[a-z0-9]+)})&.match(1)
      "https://rumble.com/embed/#{slug}/" if slug
    when "peertube_channel"
      uri = parse_url(item.url)
      "#{uri.scheme}://#{uri.host}/videos/embed/#{item.external_id}" if uri&.host
    end
  end

  def parse_url(url)
    URI.parse(url)
  rescue URI::InvalidURIError
    nil
  end

  def missing_thumb
    asset_path("missing-video.jpg")
  end

  def video?(item = nil)
    item ||= @item
    return false unless item&.source
    item.source.kind.in?(%w[youtube_channel video_channel rumble_channel
                            bitchute_channel odysee_channel peertube_channel])
  end

  def yt_dlp_download_command(item)
    %(yt-dlp -f "bv*+ba/b" "#{item.url}")
  end

  def context_params_for(item)
    forwarded = request.query_parameters.slice(:from, :source_id, :collection_id, :q, :tag, :show_muted)

    if forwarded.key?(:from)
      forwarded
    else
      forwarded.merge(inferred_from(item))
    end
  end

  def back_to_feed_path
    qp = request.query_parameters
    from = qp[:from].presence || infer_from
    case from
    when "source"
      source_path(id: qp[:source_id])
    when "collection"
      collection_path(id: qp[:collection_id])
    else
      root_path(qp.slice(:q, :tag, :show_muted))
    end
  end

  private

  def inferred_from(item)
    path = request.path.to_s
    if path.start_with?("/sources/")
      { from: "source", source_id: item.source_id }
    elsif path.start_with?("/collections/")
      collection_id = path[%r{/collections/(\d+)}, 1]
      { from: "collection", collection_id: collection_id }.compact
    else
      { from: "feed" }
    end
  end

  def infer_from
    path = request.path.to_s
    return "source" if path.start_with?("/sources/")
    return "collection" if path.start_with?("/collections/")
    "feed"
  end

  def tagging_provenance_icon(tagging)
    case tagging.source.to_sym
    when :ai_embedding
      phosphor_icon "cpu", class: "w-3 h-3 inline", title: "Tagged by embedding similarity"
    when :ai_llm
      phosphor_icon "sparkle", class: "w-3 h-3 inline", title: "Tagged by LLM"
    when :user
      phosphor_icon "user", class: "w-3 h-3 inline", title: "Tagged by you"
    end
  end
end
