class SourceSecret < ApplicationRecord
  belongs_to :source

  encrypts :value

  validates :source_id, :field_name, presence: true
  validates :field_name, uniqueness: { scope: :source_id }
end
