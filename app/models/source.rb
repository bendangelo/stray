class Source < ApplicationRecord
  belongs_to :user
  has_many :items, dependent: :destroy
  has_many :follows, dependent: :destroy
  has_many :collection_memberships, dependent: :destroy
  has_many :collections, through: :collection_memberships
  has_one :remote_collection, dependent: :destroy

  enum :kind, { youtube_channel: 0, video_channel: 1, rss_feed: 2, generic_page: 3, stray_collection: 4, rumble_channel: 5, bitchute_channel: 6, odysee_channel: 7, peertube_channel: 8 }
  enum :status, { pending: 0, ok: 1, failed: 2 }

  has_secure_token :slug, length: 24
  validates :slug, presence: true, uniqueness: true

  validates :url, :kind, presence: true
  validates :external_id, uniqueness: { scope: [ :user_id, :kind ] }

  scope :due_for_poll, -> {
    where(active: true)
      .where("next_crawl_at <= ? OR next_crawl_at IS NULL", Time.current)
  }
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :pending, -> { where(status: :pending) }
  scope :ok, -> { where(status: :ok) }
  scope :failed, -> { where(status: :failed) }
  scope :matching, ->(q) { q.blank? ? all : where("name LIKE ? OR url LIKE ?", "%#{q}%", "%#{q}%") }
  scope :stuck, -> {
    where(active: true)
      .where(status: [ :ok, :pending ])
      .where("last_polled_at IS NULL OR last_polled_at < ?", 5.minutes.ago)
      .where.not(id: Item.select(:source_id).distinct)
  }

  def display_name
    name.presence || path_segment || begin
      uri = URI.parse(url)
      uri.host&.sub(/^www\./, "")
    rescue URI::InvalidURIError
      nil
    end || external_id
  end

  def stuck_pending?
    pending? && last_polled_at.nil? && created_at < 10.minutes.ago
  end

  def bridge_class
    Stray::BridgeRegistry.find_for_source(self)&.class
  end

  def path_segment
    uri = URI.parse(url)
    return nil unless uri.host && uri.path

    parts = uri.path.split("/").reject(&:empty?)
    return nil if parts.empty?

    last = parts.last
    return nil if last.match?(/\.[a-z0-9]{1,5}\z/i)

    last.presence
  rescue URI::InvalidURIError
    nil
  end

  def self.follow!(user, kind:, url:, external_id:, name: nil, icon_url: nil, channel_url: nil, active: true, status: :pending)
    source = find_or_create_by!(user: user, external_id: external_id, kind: kind) do |s|
      s.url = url
      s.name = name
      s.icon_url = icon_url
      s.channel_url = channel_url
      s.next_crawl_at = 1.hour.from_now
      s.active = active
      s.status = status
    end
    source.update!(name: name) if name.present? && source.name != name
    source.update!(icon_url: icon_url) if icon_url.present? && source.icon_url != icon_url
    source.update!(channel_url: channel_url) if channel_url.present? && source.channel_url != channel_url
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
