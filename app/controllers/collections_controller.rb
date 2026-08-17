class CollectionsController < ApplicationController
  allow_unauthenticated_access only: %i[public_show manifest feed]

  def index
    @collections = current_user.collections.order(:name)
  end

  def new
    @collection = current_user.collections.new
  end

  def create
    @collection = current_user.collections.new(collection_params)
    if @collection.save
      redirect_to @collection, notice: "Collection created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    @collection = current_user.collections.find(params[:id])
  end

  def edit
    @collection = current_user.collections.find(params[:id])
  end

  def update
    @collection = current_user.collections.find(params[:id])
    if @collection.update(collection_params)
      redirect_to @collection, notice: "Collection updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    collection = current_user.collections.find(params[:id])
    collection.destroy!
    redirect_to collections_path, notice: "Collection deleted."
  end

  def public_show
    @collection = Collection.find_by!(slug: params[:slug])
    head :not_found unless @collection.unlisted?
  end

  def manifest
    @collection = Collection.find_by!(slug: params[:slug])
    return head :not_found unless @collection.unlisted?

    manifest = CollectionManifest.build(@collection,
      cursor: params[:cursor],
      base_url: request.base_url)
    render json: manifest
  end

  def feed
    @collection = Collection.find_by!(slug: params[:slug])
    return head :not_found unless @collection.unlisted?

    @items = @collection.items.where.not(state: :hidden).order(published_at: :desc).limit(50)
    render formats: :xml
  end

  private

  def collection_params
    params.require(:collection).permit(:name, :description, source_ids: [])
  end
end
