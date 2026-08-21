class LinksController < ApplicationController
  def create
    url = params[:url].to_s.strip
    return redirect_back_or_to(root_path, alert: "No URL provided.") if url.blank?

    if (manifest_url = Bridges::RemoteCollection.manifest_url_for(url))
      source = RemoteCollectionSubscriber.call(user: current_user, url: manifest_url)
      redirect_to source_path(source), notice: "Subscribed. Syncing first page…" and return
    end

    classification = UrlClassifier.classify(url)
    return redirect_back_or_to(root_path, alert: "Could not recognize that URL.") unless classification

    if single_video_url?(classification)
      LinkIntakeJob.perform_later(current_user.id, url, nil, follow_channel: params[:follow_channel] == "true")
      redirect_back_or_to(sources_path, notice: "Resolving #{url}…")
      return
    end

    source = create_pending_source(url, classification.source_kind)
    LinkIntakeJob.perform_later(current_user.id, url, source.id)
    redirect_back_or_to(sources_path, notice: "Resolving #{url}…")
  end

  def bulk_create
    urls = params[:urls].to_s.lines.map(&:strip).reject(&:blank?).uniq
    return redirect_to sources_path, alert: "No URLs provided." if urls.empty?

    queued = 0
    manifest_urls = []
    urls.each do |url|
      if (manifest_url = Bridges::RemoteCollection.manifest_url_for(url))
        manifest_urls << manifest_url
        next
      end

      classification = UrlClassifier.classify(url)
      next unless classification

      if single_video_url?(classification)
        LinkIntakeJob.perform_later(current_user.id, url, nil, follow_channel: true)
      else
        source = create_pending_source(url, classification.source_kind)
        LinkIntakeJob.perform_later(current_user.id, url, source.id)
      end
      queued += 1
    end

    subscribed = 0
    manifest_urls.each do |manifest_url|
      RemoteCollectionSubscriber.call(user: current_user, url: manifest_url)
      subscribed += 1
    end

    notices = []
    notices << "Subscribed to #{subscribed} collection#{'s' if subscribed != 1}." if subscribed.positive?
    notices << "Queued #{queued} link#{'s' if queued != 1}." if queued.positive?
    redirect_to sources_path, notice: notices.join(" ")
  end

  private

  SINGLE_VIDEO_CATEGORIES = %i[
    peertube_video youtube_video rumble_video bitchute_video
  ].freeze

  def single_video_url?(classification)
    classification.category.in?(SINGLE_VIDEO_CATEGORIES)
  end

  def create_pending_source(url, source_kind)
    external_id = "pending:#{Digest::SHA256.hexdigest(url)[0, 16]}"
    Source.follow!(
      current_user,
      kind: source_kind,
      url: url,
      external_id: external_id,
      status: :pending
    )
  end
end
