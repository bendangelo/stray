class TaggingsController < ApplicationController
  def create
    item = current_user.items.find_by(id: params[:tagging][:item_id])
    return head :not_found unless item

    tag_name = params[:tagging][:tag_name].to_s.downcase.strip
    return head :unprocessable_entity if tag_name.empty?

    tag = current_user.tags.find_or_create_by!(name: tag_name)
    if tag.embedding.nil?
      EmbeddingJob.perform_later("Tag", tag.id)
    end

    @tagging = Tagging.find_or_create_by!(item: item, tag: tag, source: :user)
    respond_to do |format|
      format.turbo_stream
    end
  end

  def destroy
    tagging = Tagging.find_by(id: params[:id])
    return head :not_found unless tagging && tagging.item.user_id == current_user.id

    @tagging_id = ActionView::RecordIdentifier.dom_id(tagging)
    tagging.destroy
    respond_to do |format|
      format.turbo_stream
    end
  end
end
