class Item < ApplicationRecord
  belongs_to :source
  belongs_to :user
  has_many :taggings, dependent: :destroy
  has_many :tags, through: :taggings

  enum :state, { unseen: 0, seen: 1, saved: 2, hidden: 3 }

  validates :external_id, uniqueness: { scope: :source_id }
  validates :title, :url, presence: true

  scope :incomplete_metadata, -> { where(duration: nil).or(where(thumbnail_url: nil)).or(where(published_at: nil)) }

  def incomplete_metadata?
    duration.blank? || thumbnail_url.blank? || published_at.blank?
  end

  full_search do
    field :title, weight: 5
    field :content_text, weight: 1
  end

  Suggestion = Data.define(:id, :title, :highlighted_title, :url, :published_at, :source_name)

  def self.suggest(user:, query:, limit: 8)
    return { term_hints: [], items: [] } if query.length < 3

    escaped = query.gsub(/[^\p{Alnum}\p{Space}_-]/u, " ").strip
    return { term_hints: [], items: [] } if escaped.empty?
    match_expr = "title : #{escaped}*"

    sql = <<~SQL
      SELECT items.id, items.title, items.url, items.published_at,
             sources.name AS source_name,
             highlight(items_fts, 0, '<mark>', '</mark>') AS highlighted_title
      FROM items_fts
      JOIN items ON items.id = items_fts.rowid
      JOIN sources ON sources.id = items.source_id
      JOIN follows ON follows.source_id = sources.id AND follows.user_id = ?
      WHERE items_fts MATCH ?
        AND items.user_id = ?
        AND items.state != 3
      ORDER BY rank
      LIMIT ?
    SQL

    rows = connection.exec_query(sql, "Item.suggest", [ user.id, match_expr, user.id, limit ])

    items = rows.map do |row|
      Suggestion.new(
        id: row["id"],
        title: row["title"],
        highlighted_title: row["highlighted_title"],
        url: row["url"],
        published_at: row["published_at"],
        source_name: row["source_name"]
      )
    end

    term_hints = extract_term_hints(items, query)

    { term_hints: term_hints, items: items }
  rescue ActiveRecord::StatementInvalid
    { term_hints: [], items: [] }
  end

  def self.extract_term_hints(items, query)
    prefix = query.downcase
    words = items.flat_map { |item| item.title.to_s.split }
    words
      .map(&:downcase)
      .select { |w| w.start_with?(prefix) }
      .reject { |w| w == prefix }
      .uniq
      .first(3)
  end
  private_class_method :extract_term_hints
end
