class SourcesController < ApplicationController
  include Pagy::Method

  def index
    base = Source.joins(:follows).where(follows: { user_id: current_user.id })
    @active_sources = base.active.matching(params[:q]).order(:name)
    @inactive_sources = base.inactive.order(:name)
  end

  def show
    @source = scoped_source
    @follow = @source.follows.find_by(user_id: current_user.id)
    @since = params[:since].presence || "all"
    cutoff = since_cutoff(@since)
    @since = "all" unless cutoff
    scope = @source.items.order(published_at: :desc)
    scope = scope.where("published_at >= ?", cutoff) if cutoff
    @total_count = @source.items.count
    @pagy, @items = pagy(scope, limit: 20)
  end

  def new
    @source = Source.new(active: true, kind: :rss_feed)
  end

  def create
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
    end

    if @source.valid?
      @source.update!(source_params.permit(:name, :url, :icon_url, :active))
      Follow.find_or_create_by!(user: current_user, source: @source)
      SourcePollJob.perform_later(@source.id)
      redirect_to sources_path, notice: "Source added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def pull
    source = scoped_source
    SourcePollJob.perform_later(source.id)
    redirect_back_or_to source_path(source), notice: "Pull started for #{source.name}."
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
