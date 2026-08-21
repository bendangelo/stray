class Source < ApplicationRecord
  belongs_to :user
  has_many :items, dependent: :destroy
  has_many :follows, dependent: :destroy
  has_many :collection_memberships, dependent: :destroy
  has_many :collections, through: :collection_memberships
  has_one :remote_collection, dependent: :destroy
  has_many :secrets, class_name: "SourceSecret", dependent: :destroy

  enum :kind, { youtube_channel: 0, video_channel: 1, rss_feed: 2, generic_page: 3, stray_collection: 4, rumble_channel: 5, bitchute_channel: 6, odysee_channel: 7, peertube_channel: 8, generic_list: 9, saved_video: 10 }
  enum :status, { pending: 0, ok: 1, failed: 2, degraded: 3, recovering: 4 }

  has_secure_token :slug, length: 24
  validates :slug, presence: true, uniqueness: true

  validates :url, :kind, presence: true
  validates :external_id, uniqueness: { scope: [ :user_id, :kind ] }

  scope :due_for_poll, -> {
    where(active: true)
      .where.not(kind: :saved_video)
      .where("next_crawl_at <= ? OR next_crawl_at IS NULL", Time.current)
  }
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :pending, -> { where(status: :pending) }
  scope :ok, -> { where(status: :ok) }
  scope :failed, -> { where(status: :failed) }
  scope :degraded, -> { where(status: :degraded) }
  scope :recovering, -> { where(status: :recovering) }
  scope :matching, ->(q) { q.blank? ? all : where("name LIKE ? OR url LIKE ?", "%#{q}%", "%#{q}%") }
  scope :stuck, -> {
    where(active: true)
      .where.not(kind: :saved_video)
      .where(status: [ :ok, :pending ])
      .where("last_polled_at IS NULL OR last_polled_at < ?", 5.minutes.ago)
      .where.not(id: Item.select(:source_id).distinct)
  }

  def display_name
    name.presence || path_segment || begin
      base = channel_url.presence || url
      uri = URI.parse(base)
      uri.host&.sub(/^www\./, "")
    rescue URI::InvalidURIError
      nil
    end || external_id
  end

  def stuck_pending?
    pending? && polling == false && last_polled_at.nil? && created_at < 10.minutes.ago
  end

  def bridge_class
    Stray::BridgeRegistry.find_for_source(self)&.class
  end

  def path_segment
    base = channel_url.presence || url
    uri = URI.parse(base)
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
    enqueue_backfill(source)
    source
  end

  VIDEO_CHANNEL_KINDS = %w[youtube_channel video_channel rumble_channel bitchute_channel odysee_channel peertube_channel].freeze

  def self.enqueue_backfill(source)
    return unless source.backfilled_at.nil?
    return unless VIDEO_CHANNEL_KINDS.include?(source.kind)

    SourceBackfillJob.perform_later(source.id)
  end


  def predicted_publish_at
    recent = items.order(published_at: :desc).limit(5).pluck(:published_at).compact
    return nil if recent.empty? || recent.first < 1.year.ago

    intervals = recent.each_cons(2).map { |a, b| a - b }.compact
    avg = intervals.empty? ? 1.hour : intervals.sum / intervals.size
    recent.first + avg
  end

  def recalculate_next_crawl!
    if poll_interval.present? && poll_interval.positive?
      update!(next_crawl_at: Time.current + poll_interval.seconds)
      return
    end

    predicted = predicted_publish_at

    if predicted.nil?
      if items.order(published_at: :desc).limit(1).pluck(:published_at).compact.first&.< 1.year.ago
        update!(active: false)
      else
        update!(next_crawl_at: 1.hour.from_now)
      end
      return
    end

    buffer = (Setting.get(:publication_buffer_minutes) || 10).minutes
    scheduled = predicted + buffer
    scheduled = [ scheduled, Time.current + 30.minutes ].max
    scheduled = [ scheduled, Time.current + 24.hours ].min
    update!(next_crawl_at: scheduled)
  end
end
