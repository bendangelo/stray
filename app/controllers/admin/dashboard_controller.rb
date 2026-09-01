module Admin
  class DashboardController < BaseController
    def index
      @counts = {
        users: User.count,
        sources: Source.count,
        items: Item.count,
        tags: Tag.count,
        collections: Collection.count,
        follows: Follow.count
      }
      @recent_users = User.order(created_at: :desc).limit(5)
      @recent_items = Item.order(fetched_at: :desc).limit(5)
      @poll_errors = Source.where(status: [ :failed, :recovering ])
                           .where.not(last_error: nil)
                           .order(last_error_at: :desc)
                           .limit(20)
    end
  end
end
