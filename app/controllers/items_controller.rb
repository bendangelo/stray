class ItemsController < ApplicationController
  ALLOWED_STATES = %w[ unseen saved hidden ].freeze

  def update
    item = Item.find_by(id: params[:id], user_id: current_user.id)
    return head :not_found unless item

    state = params[:state]
    return head :bad_request unless ALLOWED_STATES.include?(state)

    item.update!(state: state)

    respond_to do |format|
      format.turbo_stream { render "items/update", locals: { item:, state: } }
      format.html { redirect_to root_path }
    end
  end
end
