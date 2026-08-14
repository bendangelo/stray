class Tag < ApplicationRecord
  belongs_to :user
  has_many :taggings, dependent: :destroy

  validates :name, uniqueness: { scope: :user_id }
end
