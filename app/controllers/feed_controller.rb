class FeedController < ApplicationController
  include Pagy::Method

  def index
    @q = params[:q].presence
    @tag = params[:tag].presence
    @show_muted = params[:show_muted] == "1"

    scope = Item.joins(source: :follows)
      .where(follows: { user_id: current_user.id })
      .where(items: { user_id: current_user.id })
      .where.not(state: :hidden)
      .includes(source: :follows)

    scope = scope.where(follows: { muted: false }) unless @show_muted

    scope = scope.search(@q) if @q
    scope = scope.joins(taggings: :tag).where(tags: { name: @tag }) if @tag

    @pagy, @items = pagy(
      scope.order(Arel.sql(Ranking.order_sql)).distinct,
      limit: 20
    )

    @muted_count = current_user.follows.where(muted: true).count

    @tags = Tag.joins(taggings: { item: [ source: :follows ] })
      .where(follows: { user_id: current_user.id })
      .where(items: { user_id: current_user.id })
      .where.not(items: { state: :hidden })
      .group(:id, :name)
      .select(:name, "COUNT(*) AS item_count")
      .order("item_count DESC")
  end
end
