class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :redirect_to_setup_if_needed

  private

  def redirect_to_setup_if_needed
    return if authenticated? || User.any?
    return if controller_name == "setup"
    redirect_to new_setup_path
  end
end
