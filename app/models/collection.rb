class Collection < ApplicationRecord
  enum :visibility, { unlisted: 0, private: 1, public: 2 }, scopes: false

  belongs_to :user
  has_many :collection_memberships, dependent: :destroy
  has_many :sources, through: :collection_memberships
  has_many :items, through: :sources

  has_secure_token :slug, length: 24

  validates :name, presence: true
  validates :slug, uniqueness: { scope: :user_id }
end
