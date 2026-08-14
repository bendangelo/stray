class Tagging < ApplicationRecord
  belongs_to :item
  belongs_to :tag

  enum :source, { ai_embedding: 0, ai_llm: 1, user: 2 }

  validates :tag_id, uniqueness: { scope: [ :item_id, :source ] }
end
