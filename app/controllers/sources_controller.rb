class SourcesController < ApplicationController
  include Pagy::Method
  allow_unauthenticated_access only: %i[public_show feed manifest]

  def index
    base = Source.joins(:follows).where(follows: { user_id: current_user.id })
    @active_sources = base.active.matching(params[:q]).order(:name)
    @inactive_sources = base.inactive.order(:name)
  end

  def show
    @source = scoped_source
    @follow = @source.follows.find_by(user_id: current_user.id)
    @collections = current_user.collections.order(:name)
    @member_collection_ids = @source.collection_memberships.pluck(:collection_id).to_set
    @since = params[:since].presence || "all"
    cutoff = since_cutoff(@since)
    @since = "all" unless cutoff
    scope = @source.items.includes(source: :follows).order(published_at: :desc)
    scope = scope.where("published_at >= ?", cutoff) if cutoff
    @total_count = @source.items.count
    @pagy, @items = pagy(scope, limit: 20)
  end

  def new
    @source = Source.new(active: true, kind: :rss_feed)
  end

  def create
    url = source_params[:url].to_s.strip

    if (manifest_url = Bridges::RemoteCollection.manifest_url_for(url))
      source = RemoteCollectionSubscriber.call(user: current_user, url: manifest_url)
      redirect_to source_path(source), notice: "Subscribed. Syncing first page…"
      return
    end

    if source_params[:kind] == "youtube_channel"
      create_youtube_channel
    else
      create_regular_source
    end
  end

  def create_youtube_channel
    url = source_params[:url]
    external_id = "pending:#{Digest::SHA256.hexdigest(url)[0, 16]}"
    @source = Source.follow!(
      current_user,
      kind: :youtube_channel,
      url: url,
      external_id: external_id,
      name: source_params[:name],
      icon_url: source_params[:icon_url],
      active: source_params.key?(:active) ? (source_params[:active] == "1") : true,
      status: :pending
    )
    @source.update!(next_crawl_at: 1.minute.from_now)
    LinkIntakeJob.perform_later(current_user.id, url, @source.id)
    redirect_to sources_path, notice: "Source added."
  end

  def create_regular_source
    external_id = Digest::SHA256.hexdigest(source_params[:url])[0, 16]
    @source = Source.find_or_create_by!(
      user: current_user,
      external_id: external_id,
      kind: source_params[:kind]
    ) do |s|
      s.url = source_params[:url]
      s.name = source_params[:name]
      s.icon_url = source_params[:icon_url]
      s.active = source_params.key?(:active) ? (source_params[:active] == "1") : true
      s.status = :pending
      s.next_crawl_at = 1.minute.from_now
    end

    if @source.valid?
      @source.update!(source_params.permit(:name, :url, :icon_url, :active, :poll_interval))
      Follow.find_or_create_by!(user: current_user, source: @source)
      SourcePollJob.perform_later(@source.id)
      redirect_to sources_path, notice: "Source added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def pull
    source = scoped_source
    Source::StatusMachine.reset_for_poll!(source)
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_#{source.user_id}_sources",
      target: ActionView::RecordIdentifier.dom_id(source),
      partial: "sources/source",
      locals: { source: source }
    )
    SourcePollJob.perform_later(source.id)
    redirect_back_or_to source_path(source), notice: "Pull started for #{source.display_name}."
  end

  def mute
    source = scoped_source
    follow = source.follows.find_by(user_id: current_user.id)
    return head :not_found unless follow

    item = source.items.first
    if item
      Ranking.apply_interaction!(user: current_user, item: item, kind: :muted_source)
    else
      follow.update!(weight: Ranking.clamp(follow.weight - Ranking::MUTE_PENALTY))
    end
    follow.update!(muted: true)

    respond_to do |format|
      format.turbo_stream { render "sources/update_weight", locals: { source: } }
      format.html { redirect_to source_path(source) }
    end
  end

  def unmute
    source = scoped_source
    follow = source.follows.find_by(user_id: current_user.id)
    return head :not_found unless follow

    follow.update!(muted: false)

    respond_to do |format|
      format.turbo_stream { render "sources/update_weight", locals: { source: } }
      format.html { redirect_to source_path(source) }
    end
  end

  def mark_read
    source = scoped_source
    source.items.where(state: :unseen).update_all(state: Item.states[:seen])
    redirect_back_or_to source_path(source), notice: "Marked all items as read."
  end

  def public_show
    @source = Source.find_by!(slug: params[:slug])
  end

  def feed
    @source = Source.find_by!(slug: params[:slug])
    @items = @source.items.order(published_at: :desc).limit(50)
    render formats: :xml
  end

  def manifest
    source = Source.find_by!(slug: params[:slug])
    render json: SourceManifest.build(source, cursor: params[:cursor], base_url: request.base_url)
  end

  def rotate_slug
    source = scoped_source
    source.regenerate_slug
    redirect_to source_path(source), notice: "Feed link rotated."
  end

  def edit
    @source = scoped_source
  end

  def update
    source = scoped_source

    if params[:reset_weight]
      source.follows.find_by(user_id: current_user.id)&.update!(weight: 1.0)
      respond_to do |format|
        format.turbo_stream { render "sources/update_weight", locals: { source: } }
        format.html { redirect_to source_path(source) }
      end
    elsif source.update(source_params)
      redirect_to sources_path, notice: "Source updated."
    else
      @source = source
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    source = scoped_source
    source.destroy!
    redirect_to sources_path, notice: "Source deleted."
  end

  private

  def scoped_source
    Source.joins(:follows).where(follows: { user_id: current_user.id }).find(params[:id])
  end

  def source_params
    params.require(:source).permit(:name, :url, :kind, :icon_url, :active, :poll_interval)
  end

  def since_cutoff(since)
    case since
    when "1m" then 1.month.ago
    when "3m" then 3.months.ago
    when "1y" then 1.year.ago
    end
  end
end
