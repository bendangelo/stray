class LinksController < ApplicationController
  def create
    url = params[:url]
    return head :bad_request if url.blank?

    LinkIntakeJob.perform_later(current_user.id, url)

    respond_to do |format|
      format.turbo_stream
    end
  end
end
