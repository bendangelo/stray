class FeedController < ApplicationController
  include Pagy::Method

  def index
    @q = params[:q].presence
    @tag = params[:tag].presence

    scope = Item.joins(source: :follow)
      .where(follows: { user_id: current_user.id })
      .where(items: { user_id: current_user.id })
      .where.not(state: :hidden)

    scope = scope.search(@q) if @q
    scope = scope.joins(taggings: :tag).where(tags: { name: @tag }) if @tag

    @pagy, @items = pagy(scope.order(published_at: :desc).distinct, limit: 20)

    @tags = Tag.joins(taggings: { item: [ source: :follow ] })
      .where(follows: { user_id: current_user.id })
      .where(items: { user_id: current_user.id })
      .where.not(items: { state: :hidden })
      .group(:id, :name)
      .select(:name, "COUNT(*) AS item_count")
      .order("item_count DESC")
  end
end
