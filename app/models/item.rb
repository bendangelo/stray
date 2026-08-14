class Item < ApplicationRecord
  belongs_to :source
  belongs_to :user
  has_many :taggings, dependent: :destroy

  enum :state, { unseen: 0, seen: 1, saved: 2, hidden: 3 }

  validates :external_id, uniqueness: { scope: :source_id }
  validates :title, :url, presence: true

  full_search do
    field :title, weight: 5
    field :content_text, weight: 1
  end
end
