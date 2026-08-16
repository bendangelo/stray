class SearchController < ApplicationController
  def suggest
    query = params[:q].to_s.strip
    @suggestions = Item.suggest(user: current_user, query: query, limit: 8)
    render partial: "search/suggestions", formats: [:html]
  end
end
