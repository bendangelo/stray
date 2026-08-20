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
    source = params[:collection][:source_id].present? ? scoped_source_by_id(params[:collection][:source_id]) : nil

    if source.nil? && params[:collection][:source_id].present?
      return head :not_found
    end

    if @collection.save
      if source
        CollectionMembership.find_or_create_by!(collection: @collection, source: source)
      end

      respond_to do |format|
        format.html { redirect_to @collection, notice: "Collection created." }
        format.turbo_stream { head :ok }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_content }
        format.turbo_stream { head :unprocessable_content }
      end
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

    @items = @collection.items.order(published_at: :desc).limit(50)
    render formats: :xml
  end

  private

  def collection_params
    params.require(:collection).permit(:name, :description, source_ids: [])
  end

  def scoped_source_by_id(id)
    Source.joins(:follows).find_by(id: id, follows: { user_id: current_user.id })
  end
end
