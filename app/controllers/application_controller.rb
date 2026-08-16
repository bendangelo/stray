class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  prepend_before_action :redirect_to_setup_if_needed
  before_action :set_sidebar_sources, if: :authenticated?

  private

  def set_sidebar_sources
    @sources = Source.joins(:follow)
      .where(follows: { user_id: current_user.id })
      .where(active: true)
      .order(:name)
  end

  def redirect_to_setup_if_needed
    return if authenticated? || User.any?
    return if controller_name == "setup"
    redirect_to new_setup_path
  end

  def require_admin
    return if current_user&.admin?

    redirect_to root_path, alert: "Not authorized."
  end
end
