class PromoteSavedVideoJob < ApplicationJob
  queue_as :default

  def perform(item_id)
  end
end
