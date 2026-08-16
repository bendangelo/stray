class SourcesController < ApplicationController
  include Pagy::Method

  def index
  end

  def show
    @source = Source.joins(:follow)
      .where(follows: { user_id: current_user.id })
      .find(params[:id])

    @follow = @source.follow
    @pagy, @items = pagy(@source.items.order(published_at: :desc), limit: 20)
  end

  def update
    source = Source.joins(:follow)
      .where(follows: { user_id: current_user.id })
      .find(params[:id])

    source.follow.update!(weight: 1.0) if params[:reset_weight]

    respond_to do |format|
      format.turbo_stream { render "sources/update", locals: { source: } }
      format.html { redirect_to source_path(source) }
    end
  end
end
