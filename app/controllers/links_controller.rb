class LinksController < ApplicationController
  def create
    url = params[:url].to_s.strip
    return redirect_back_or_to(root_path, alert: "No URL provided.") if url.blank?

    if (manifest_url = remote_collection_manifest_url(url))
      redirect_to new_remote_collection_path(manifest_url: manifest_url) and return
    end

    if (external_id = youtube_channel_id_from_url(url))
      source = Source.follow!(
        current_user,
        kind: :youtube_channel,
        url: Stray::Youtube::ChannelResolver.build_rss_url(external_id),
        external_id: external_id
      )
      LinkIntakeJob.perform_later(current_user.id, url, source.id)
      redirect_to source_path(source) and return
    end

    if youtube_video_id_from_url(url)
      LinkIntakeJob.perform_later(current_user.id, url)
      redirect_back_or_to(root_path, notice: "Resolving video…") and return
    end

    LinkIntakeJob.perform_later(current_user.id, url)
    redirect_back_or_to(sources_path, notice: "Resolving #{url}…")
  end

  def bulk_create
    urls = params[:urls].to_s.lines.map(&:strip).reject(&:blank?).uniq
    return redirect_to sources_path, alert: "No URLs provided." if urls.empty?

    queued = 0
    manifest_urls = []
    urls.each do |url|
      if (manifest_url = remote_collection_manifest_url(url))
        manifest_urls << manifest_url
        next
      end

      if (external_id = youtube_channel_id_from_url(url))
        source = Source.follow!(
          current_user,
          kind: :youtube_channel,
          url: Stray::Youtube::ChannelResolver.build_rss_url(external_id),
          external_id: external_id
        )
        LinkIntakeJob.perform_later(current_user.id, url, source.id)
      else
        LinkIntakeJob.perform_later(current_user.id, url)
      end
      queued += 1
    end

    if manifest_urls.any?
      flash[:notice] = "Queued #{queued} link#{'s' if queued != 1}." if queued.positive?
      redirect_to new_remote_collection_path(manifest_url: manifest_urls.first) and return
    end

    redirect_to sources_path, notice: "Queued #{queued} link#{'s' if queued != 1}."
  end

  private

  def remote_collection_manifest_url(url)
    return url if Stray::Extractors::RemoteCollection.matches?(url)
    manifest_url_for_friendly_collection(url)
  end

  def manifest_url_for_friendly_collection(url)
    uri = URI.parse(url)
    return nil unless uri.host
    return nil unless uri.path =~ %r{^/c/([A-Za-z0-9]{24})$}

    "#{uri.scheme}://#{uri.host}/c/#{$1}/manifest.json"
  rescue URI::InvalidURIError
    nil
  end

  def youtube_channel_id_from_url(url)
    uri = URI.parse(url)
    return nil unless uri.host&.end_with?("youtube.com")

    uri.path.match(%r{^/channel/(UC[a-zA-Z0-9_-]+)})&.captures&.first
  rescue URI::InvalidURIError
    nil
  end

  def youtube_video_id_from_url(url)
    uri = URI.parse(url)
    if uri.host == "youtu.be"
      uri.path.sub(%r{^/}, "")
    elsif uri.host&.end_with?("youtube.com") && uri.path == "/watch"
      uri.query.to_s.split("&").find { |p| p.start_with?("v=") }&.sub("v=", "")
    end
  rescue URI::InvalidURIError
    nil
  end
end
