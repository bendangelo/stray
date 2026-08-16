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
    @pagy, @items = pagy(@source.items.order(published_at: :desc), limit: 20)
  end

  def new
    @source = Source.new(active: true, kind: :rss_feed)
  end

  def create
    @source = Source.new(source_params.merge(user: current_user, external_id: SecureRandom.hex(8)))

    if @source.save
      Follow.find_or_create_by!(user: current_user, source: @source)
      SourcePollJob.perform_later(@source.id)
      redirect_to sources_path, notice: "Source added."
    else
      render :new, status: :unprocessable_content
    end
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
      respond_to do |format|
        format.turbo_stream { render "sources/update", locals: { source: } }
        format.html { redirect_to sources_path }
      end
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
    params.require(:source).permit(:name, :url, :kind, :icon_url, :active)
  end
end
