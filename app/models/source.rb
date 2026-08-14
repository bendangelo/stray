class Source < ApplicationRecord
  belongs_to :user
  has_many :items, dependent: :destroy
  has_one :follow, dependent: :destroy

  enum :kind, { youtube_channel: 0, video_channel: 1, rss_feed: 2, generic_page: 3 }

  validates :url, :kind, presence: true
  validates :external_id, uniqueness: { scope: [:user_id, :kind] }

  scope :due_for_poll, -> {
    where(active: true)
      .where("next_crawl_at <= ? OR next_crawl_at IS NULL", Time.current)
  }

  def recalculate_next_crawl!
    recent = items.order(published_at: :desc).limit(5).pluck(:published_at).compact

    if recent.empty?
      update!(next_crawl_at: 1.hour.from_now)
    elsif recent.first < 1.year.ago
      update!(active: false)
    else
      intervals = recent.each_cons(2).map { |a, b| a - b }.compact
      avg = intervals.empty? ? 1.hour : intervals.sum / intervals.size
      predicted = recent.first + avg
      predicted = [predicted, Time.current + 30.minutes].max
      predicted = [predicted, Time.current + 24.hours].min
      update!(next_crawl_at: predicted)
    end
  end
end
