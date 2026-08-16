# frozen_string_literal: true

module Stray
  module Ranking
    OPEN_BOOST     = 0.05
    STAR_BOOST     = 0.10
    HIDE_PENALTY   = 0.10
    MUTE_PENALTY   = 0.30
    MUTE_WINDOW    = 7.days
    MUTE_THRESHOLD = 3
    WEIGHT_MIN     = 0.1
    WEIGHT_MAX     = 3.0
    BOOST_HOURS    = 24

    DELTAS = {
      opened:        OPEN_BOOST,
      starred:       STAR_BOOST,
      hidden:       -HIDE_PENALTY,
      muted_source: -MUTE_PENALTY
    }.freeze

    def self.clamp(weight)
      weight.clamp(WEIGHT_MIN, WEIGHT_MAX)
    end

    def self.order_sql
      "datetime(items.published_at, printf('%+.1f hours', (follows.weight - 1.0) * #{BOOST_HOURS})) DESC, items.published_at DESC"
    end

    def self.muted_enough?(user:, source_id:)
      Interaction.joins(:item)
        .where(user_id: user.id, kind: :hidden)
        .where("interactions.created_at >= ?", MUTE_WINDOW.ago)
        .where(items: { source_id: source_id })
        .count >= MUTE_THRESHOLD
    end

    def self.apply_interaction!(user:, item:, kind:)
      return if kind.nil?

      follow = Follow.find_by(user_id: user.id, source_id: item.source_id)
      return unless follow

      created = Interaction.find_or_create_by!(item: item, user: user, kind: kind)
      return unless created.previously_new_record?

      follow.weight = clamp(follow.weight + DELTAS.fetch(kind))
      follow.muted = muted_enough?(user: user, source_id: item.source_id)
      follow.save!
    end
  end
end
