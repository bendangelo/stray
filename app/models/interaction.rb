class Interaction < ApplicationRecord
  belongs_to :item
  belongs_to :user
  enum :kind, { opened: 0, starred: 1, hidden: 2, muted_source: 3 }
  validates :kind, uniqueness: { scope: [:item_id, :user_id] }
end
