class FeedController < ApplicationController
  include Pagy::Method

  def index
    @q = params[:q].presence
    @tag = params[:tag].presence
    @show_muted = params[:show_muted] == "1"
    @saved = params[:saved] == "1"

    if @q && !@tag && !@saved && (source = exact_source_match(@q))
      return redirect_to source_path(source)
    end

    if @saved
      index_saved
    elsif @q || @tag
      index_filtered
    else
      index_browse
    end

    @muted_count = current_user.follows.where(muted: true).count

    @tags = Tag.joins(taggings: { item: [ source: :follows ] })
      .where(follows: { user_id: current_user.id })
      .where(items: { user_id: current_user.id })
      .where.not(items: { state: :hidden })
      .group(:id, :name)
      .select(:name, "COUNT(*) AS item_count")
      .order("item_count DESC")
  end

  private

  def exact_source_match(query)
    needle = query.strip
    current_user.follows.includes(:source)
      .where.not(sources: { kind: :saved_video })
      .map(&:source)
      .find { |source| source.display_name.to_s.casecmp?(needle) }
  end

  def index_browse
    entries = FeedInterleaver.call(user: current_user, show_muted: @show_muted)
    @pagy, page_entries = pagy(entries, limit: 48)
    @items = page_entries.map(&:item)
    @rank_positions = page_entries.index_by { |entry| entry.item.id }
                                 .transform_values(&:source_position)
    @mixed = true
    @browse_empty = @items.empty? && current_user.follows.exists?
  end

  def index_saved
    scope = base_scope.where(items: { state: Item.states[:saved] })
    scope = scope.search(@q) if @q
    scope = scope.joins(taggings: :tag).where(tags: { name: @tag }) if @tag
    @pagy, @items = pagy(scope.order(published_at: :desc).distinct, limit: 48)
    @rank_positions = nil
    @mixed = false
    @browse_empty = false
  end

  def index_filtered
    scope = base_scope
    scope = scope.where(follows: { muted: false }) unless @show_muted
    scope = scope.search(@q) if @q
    scope = scope.joins(taggings: :tag).where(tags: { name: @tag }) if @tag
    @pagy, @items = pagy(scope.order(published_at: :desc).distinct, limit: 48)
    @rank_positions = nil
    @mixed = false
    @browse_empty = false
  end

  def base_scope
    Item.joins(source: :follows)
      .where(follows: { user_id: current_user.id })
      .where(items: { user_id: current_user.id })
      .where.not(state: :hidden)
      .includes(source: :follows)
  end
end
