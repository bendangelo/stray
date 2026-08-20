class RemoteCollectionsController < ApplicationController
  def destroy
    rc = current_user.remote_collections.find_by!(source_id: params[:source_id])
    source = rc.source
    rc.destroy!
    source.destroy!
    redirect_to sources_path, notice: "Unsubscribed from remote collection."
  end
end
