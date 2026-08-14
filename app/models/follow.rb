class Follow < ApplicationRecord
  belongs_to :user
  belongs_to :source

  validates :source_id, uniqueness: { scope: :user_id }
end
