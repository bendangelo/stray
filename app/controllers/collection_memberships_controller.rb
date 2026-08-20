class CollectionMembershipsController < ApplicationController
  def create
    collection = current_user.collections.find_by(id: params.dig(:collection_membership, :collection_id))
    return head :not_found unless collection

    source = Source.joins(:follows).find_by(id: params.dig(:collection_membership, :source_id), follows: { user_id: current_user.id })
    return head :not_found unless source

    CollectionMembership.find_or_create_by!(collection: collection, source: source)
    @source = source
    @collection = collection
    respond_to { |format| format.turbo_stream }
  end

  def destroy
    membership = CollectionMembership.joins(:collection).find_by(id: params[:id], collection: { user_id: current_user.id })
    return head :not_found unless membership

    @source = membership.source
    @collection = membership.collection
    membership.destroy
    respond_to { |format| format.turbo_stream }
  end
end
