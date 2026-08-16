class Source < ApplicationRecord
  belongs_to :user
  has_many :items, dependent: :destroy
  has_many :follows, dependent: :destroy
  has_many :collection_memberships, dependent: :destroy
  has_one :remote_collection, dependent: :destroy

  enum :kind, { youtube_channel: 0, video_channel: 1, rss_feed: 2, generic_page: 3, stray_collection: 4 }

  validates :url, :kind, presence: true
  validates :external_id, uniqueness: { scope: [ :user_id, :kind ] }

  scope :due_for_poll, -> {
    where(active: true)
      .where("next_crawl_at <= ? OR next_crawl_at IS NULL", Time.current)
  }
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :matching, ->(q) { q.blank? ? all : where("name LIKE ? OR url LIKE ?", "%#{q}%", "%#{q}%") }

  def display_name
    name.presence || begin
      uri = URI.parse(url)
      host = uri.host&.sub(/^www\./, "")
      host || external_id
    rescue URI::InvalidURIError
      external_id
    end
  end

  def self.follow!(user, kind:, url:, external_id:, name: nil, icon_url: nil, active: true)
    source = find_or_create_by!(user: user, external_id: external_id, kind: kind) do |s|
      s.url = url
      s.name = name
      s.icon_url = icon_url
      s.next_crawl_at = 1.hour.from_now
      s.active = active
    end
    source.update!(url: url, name: name) if name.present?
    Follow.find_or_create_by!(user: user, source: source)
    source
  end


  def recalculate_next_crawl!
    if poll_interval.present? && poll_interval.positive?
      update!(next_crawl_at: Time.current + poll_interval.seconds)
      return
    end

    recent = items.order(published_at: :desc).limit(5).pluck(:published_at).compact

    if recent.empty?
      update!(next_crawl_at: 1.hour.from_now)
    elsif recent.first < 1.year.ago
      update!(active: false)
    else
      intervals = recent.each_cons(2).map { |a, b| a - b }.compact
      avg = intervals.empty? ? 1.hour : intervals.sum / intervals.size
      predicted = recent.first + avg
      predicted = [ predicted, Time.current + 30.minutes ].max
      predicted = [ predicted, Time.current + 24.hours ].min
      update!(next_crawl_at: predicted)
    end
  end
end
