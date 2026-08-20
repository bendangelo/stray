class CollectionMembershipsController < ApplicationController
  def create
    collection = current_user.collections.find_by(id: params.dig(:collection_membership, :collection_id))
    return head :not_found unless collection

    source = Source.joins(:follows).find_by(id: params.dig(:collection_membership, :source_id), follows: { user_id: current_user.id })
    return head :not_found unless source

    CollectionMembership.find_or_create_by!(collection: collection, source: source)
    head :ok
  end
end
