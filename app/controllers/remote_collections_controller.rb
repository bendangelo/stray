class RemoteCollectionsController < ApplicationController
  def new
  end

  def create
    url = params.dig(:remote_collection, :manifest_url).to_s.strip

    begin
      @preview = fetch_manifest_preview(url)
      @manifest_url = url
      render :preview
    rescue UrlGuard::Blocked, StandardError => e
      @error = "Could not fetch manifest: #{e.message}"
      render :new, status: :unprocessable_content
    end
  end

  def subscribe
    url = params.dig(:remote_collection, :manifest_url).to_s.strip
    collection_name = params.dig(:remote_collection, :collection_name)
    producer_instance_name = params.dig(:remote_collection, :producer_instance_name)

    if existing = current_user.remote_collections.find_by(manifest_url: url)
      redirect_to source_path(existing.source), notice: "Already subscribed."
      return
    end

    source = Source.create!(
      user: current_user,
      kind: :stray_collection,
      url: url,
      name: collection_name || "Remote collection",
      external_id: derive_external_id(url),
      active: true
    )
    Follow.create!(user: current_user, source: source)
    RemoteCollection.create!(
      source: source,
      user: current_user,
      manifest_url: url,
      collection_name: collection_name,
      producer_instance_name: producer_instance_name
    )
    SourcePollJob.perform_later(source.id)
    redirect_to source_path(source), notice: "Subscribed. Syncing first page…"
  end

  def destroy
    rc = current_user.remote_collections.find_by!(source_id: params[:source_id])
    source = rc.source
    rc.destroy!
    source.destroy!
    redirect_to sources_path, notice: "Unsubscribed from remote collection."
  end

  private

  def fetch_manifest_preview(url)
    raise UrlGuard::Blocked, "URL blocked" unless UrlGuard.allowed?(url)

    response = Faraday.new do |conn|
      conn.response :follow_redirects, max: 3
      conn.options.timeout = 10
      conn.adapter :net_http
    end.get(url)

    raise "fetch failed: HTTP #{response.status}" unless response.status == 200

    data = JSON.parse(response.body)
    raise "not a stray-collection manifest" unless data["format"] == "stray-collection"

    {
      collection_name: data.dig("collection", "name"),
      producer_instance_name: data.dig("producer", "instance_name"),
      source_count: (data["sources"] || []).size,
      item_count: data.dig("collection", "item_count"),
      item_samples: (data["items"] || []).first(5).map { |i| { title: i["title"], url: i["url"] } }
    }
  rescue JSON::ParserError
    raise "invalid JSON"
  end

  def derive_external_id(url)
    Digest::SHA256.hexdigest(url)[0, 16]
  end
end
