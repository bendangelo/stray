class ItemsController < ApplicationController
  ALLOWED_STATES = %w[ unseen saved hidden ].freeze
  KIND_MAP = { "saved" => :starred, "hidden" => :hidden }.freeze

  def player
    item = Item.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless item

    item.update!(state: :seen) if item.unseen?
    Ranking.apply_interaction!(user: current_user, item: item, kind: :opened)
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
end
