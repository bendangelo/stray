class FeedController < ApplicationController
  include Pagy::Method

  def index
    @q = params[:q].presence

    scope = Item.joins(source: :follow)
      .where(follows: { user_id: current_user.id })
      .where(items: { user_id: current_user.id })
      .where.not(state: :hidden)

    scope = scope.search(@q) if @q

    @pagy, @items = pagy(scope.order(published_at: :desc), limit: 20)
  end
end
