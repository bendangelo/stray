class RemoteCollection < ApplicationRecord
  belongs_to :source
  belongs_to :user

  validates :manifest_url, presence: true, uniqueness: { scope: :user_id }
  validates :source_id, uniqueness: true
end
