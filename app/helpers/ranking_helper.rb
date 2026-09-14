# frozen_string_literal: true

require "ostruct"

module RankingHelper
  def ranking_explanation_for(item, follow, source_position: nil, mixed: false)
    OpenStruct.new(
      source_name: item.source.display_name,
      weight: follow.weight,
      muted: follow.muted,
      source_position: source_position,
      mixed: mixed
    )
  end
end
