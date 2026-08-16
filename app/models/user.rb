class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :items, dependent: :destroy
  has_many :sources, dependent: :destroy
  has_many :collections, dependent: :destroy
  has_many :remote_collections, dependent: :destroy

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, uniqueness: true
  validates :username, presence: true
  validates :password, length: { minimum: 6 }
end
