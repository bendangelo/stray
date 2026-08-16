class TagsController < ApplicationController
  include Pagy::Method

  def index
    @tags = current_user.tags
      .left_joins(:taggings)
      .select("tags.*, COUNT(taggings.id) AS taggings_count")
      .group("tags.id")
      .order("COUNT(taggings.id) DESC")
    @pagy, @tags = pagy(@tags, limit: 25)
  end

  def new
    @tag = current_user.tags.new
  end

  def create
    @tag = current_user.tags.new(tag_params)
    if @tag.save
      EmbeddingJob.perform_later("Tag", @tag.id)
      redirect_to tags_path, notice: "Tag created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @tag = current_user.tags.find(params[:id])
  end

  def update
    @tag = current_user.tags.find(params[:id])
    if @tag.update(tag_params)
      @tag.update!(embedding: nil)
      EmbeddingJob.perform_later("Tag", @tag.id)
      redirect_to tags_path, notice: "Tag updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @tag = current_user.tags.find(params[:id])
    @tag.destroy
    redirect_to tags_path, notice: "Tag deleted."
  end

  def merge
    source = current_user.tags.find(params[:id])
    target = current_user.tags.find(params[:target_id])

    source.taggings.each do |tagging|
      Tagging.find_or_create_by!(item: tagging.item, tag: target, source: tagging.source)
    end
    source.destroy
    redirect_to tags_path, notice: "Merged into #{target.name}."
  end

  def search
    query = params[:q].to_s.strip
    @tags = if query.present?
      current_user.tags.where("name LIKE ?", "#{query}%").limit(10)
    else
      current_user.tags.limit(10)
    end
    render json: @tags.as_json(only: [ :id, :name ])
  end

  private

  def tag_params
    params.require(:tag).permit(:name)
  end
end
