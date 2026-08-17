class Follow < ApplicationRecord
  belongs_to :user
  belongs_to :source

  validates :source_id, uniqueness: { scope: :user_id }
  before_save :clamp_weight

  private

  def clamp_weight
    self.weight = Ranking.clamp(weight)
  end
end
