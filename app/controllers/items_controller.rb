class ItemsController < ApplicationController
  include ApplicationHelper

  ALLOWED_STATES = %w[ unseen saved hidden ].freeze
  KIND_MAP = { "saved" => :starred, "hidden" => :hidden }.freeze

  def show
    @item = Item.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless @item

    record_open!(@item)
    @neighbors = find_neighbors(@item)
  end

  def player
    item = Item.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless item

    record_open!(item)
    render partial: "items/player", locals: { item: }, layout: false
  end

  def update
    item = Item.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless item

    state = params[:state]
    return head :bad_request unless ALLOWED_STATES.include?(state)

    item.update!(state: state)
    Ranking.apply_interaction!(user: current_user, item: item, kind: KIND_MAP[state])

    respond_to do |format|
      format.turbo_stream { render "items/update", locals: { item:, state: } }
      format.html { redirect_to root_path }
    end
  end

  def follow_channel
    item = Item.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless item

    unless item.source.kind == "saved_video" && youtube_video_item?(item)
      redirect_to item_path(item), alert: "This item can't follow a channel."
      return
    end

    PromoteSavedVideoJob.perform_later(item.id)
    redirect_to item_path(item), notice: "Following channel — syncing…"
  end

  private

  def record_open!(item)
    item.update!(state: :seen) if item.unseen?
    Ranking.apply_interaction!(user: current_user, item: item, kind: :opened)
  end

  def find_neighbors(item)
    scope, order = neighbor_scope_and_order
    return [ nil, nil ] unless scope

    ids = scope.order(Arel.sql(order)).distinct.pluck(:id)
    idx = ids.index(item.id)
    return [ nil, nil ] unless idx

    prev_id = idx > 0 ? ids[idx - 1] : nil
    next_id = idx < ids.length - 1 ? ids[idx + 1] : nil
    [ prev_id && Item.find_by(id: prev_id), next_id && Item.find_by(id: next_id) ]
  end

  def neighbor_scope_and_order
    case params[:from]
    when "source"
      return [ nil, nil ] unless params[:source_id]
      source = Source.joins(:follows).find_by(id: params[:source_id], follows: { user_id: current_user.id })
      return [ nil, nil ] unless source
      scope = source.items.where(user_id: current_user.id).where.not(state: :hidden)
      [ scope, "items.published_at DESC" ]
    when "collection"
      return [ nil, nil ] unless params[:collection_id]
      collection = current_user.collections.find_by(id: params[:collection_id])
      return [ nil, nil ] unless collection
      scope = Item.joins(source: [ :follows, :collection_memberships ])
        .where(follows: { user_id: current_user.id })
        .where(collection_memberships: { collection_id: collection.id })
        .where(items: { user_id: current_user.id })
        .where.not(state: :hidden)
      [ scope, Ranking.order_sql ]
    else # "feed" or unspecified
      scope = Item.joins(source: :follows)
        .where(follows: { user_id: current_user.id })
        .where(items: { user_id: current_user.id })
        .where.not(state: :hidden)
      scope = scope.where(follows: { muted: false }) unless params[:show_muted] == "1"
      scope = scope.search(params[:q]) if params[:q].present?
      if params[:tag].present?
        scope = scope.joins(taggings: :tag).where(tags: { name: params[:tag] })
      end
      [ scope, Ranking.order_sql ]
    end
  end
end
