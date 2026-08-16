# frozen_string_literal: true

require "ostruct"

module RankingHelper
  def ranking_explanation_for(item, follow)
    offset_hours = ((follow.weight - 1.0) * Stray::Ranking::BOOST_HOURS).round(1)
    OpenStruct.new(
      published_at: item.published_at,
      weight: follow.weight,
      offset_hours: offset_hours,
      effective_at: item.published_at&.then { |t| t + offset_hours.hours },
      muted: follow.muted
    )
  end

  def offset_label(hours)
    return "no weight adjustment" if hours.zero?

    sign = hours.positive? ? "+" : "−"
    "#{sign}#{hours.abs}h"
  end
end
