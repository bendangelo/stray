class CollectionMembership < ApplicationRecord
  belongs_to :collection
  belongs_to :source

  validates :source_id, uniqueness: { scope: :collection_id }
end
