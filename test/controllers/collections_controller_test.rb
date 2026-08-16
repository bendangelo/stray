require "test_helper"

class CollectionsControllerTest < ActionDispatch::IntegrationTest
  test "index lists current user collections" do
    sign_in_as(users(:one))
    get collections_path
    assert_response :success
    assert_includes response.body, "Economics Blogs"
    assert_includes response.body, "Private Notes"
  end

  test "index requires authentication" do
    get collections_path
    assert_redirected_to new_session_path
  end

  test "new renders form" do
    sign_in_as(users(:one))
    get new_collection_path
    assert_response :success
    assert_includes response.body, "New collection"
  end

  test "create with valid params creates collection" do
    sign_in_as(users(:one))
    assert_difference -> { Collection.count }, 1 do
      post collections_path, params: { collection: { name: "My Feeds", description: "stuff" } }
    end
    assert_redirected_to collection_path(Collection.last)
  end

  test "create with invalid params re-renders new" do
    sign_in_as(users(:one))
    post collections_path, params: { collection: { name: "" } }
    assert_response :unprocessable_content
  end

  test "show displays collection and member sources" do
    sign_in_as(users(:one))
    get collection_path(collections(:econ))
    assert_response :success
    assert_includes response.body, "Economics Blogs"
    assert_includes response.body, "Test Channel"
  end

  test "show includes share URLs" do
    sign_in_as(users(:one))
    get collection_path(collections(:econ))
    assert_response :success
    assert_includes response.body, "/c/econblogssecrettoken1234/manifest"
    assert_includes response.body, "/c/econblogssecrettoken1234/feed"
  end

  test "show 404 for other user's collection" do
    sign_in_as(users(:two))
    get collection_path(collections(:econ))
    assert_response :not_found
  end

  test "edit renders form" do
    sign_in_as(users(:one))
    get edit_collection_path(collections(:econ))
    assert_response :success
    assert_includes response.body, "Edit collection"
  end

  test "update changes name and description" do
    sign_in_as(users(:one))
    patch collection_path(collections(:econ)), params: { collection: { name: "Renamed", description: "new desc" } }
    assert_redirected_to collection_path(collections(:econ))
    collections(:econ).reload
    assert_equal "Renamed", collections(:econ).name
    assert_equal "new desc", collections(:econ).description
  end

  test "update can add sources" do
    sign_in_as(users(:one))
    patch collection_path(collections(:econ)), params: { collection: { source_ids: [ sources(:youtube).id, sources(:bitchute).id ] } }
    assert_redirected_to collection_path(collections(:econ))
    assert_equal 2, collections(:econ).sources.count
  end

  test "destroy deletes collection" do
    sign_in_as(users(:one))
    assert_difference -> { Collection.count }, -1 do
      delete collection_path(collections(:econ))
    end
    assert_redirected_to collections_path
  end

  test "public_show serves unlisted collection unauthenticated" do
    get public_collection_path(slug: collections(:econ).slug)
    assert_response :success
    assert_includes response.body, "Economics Blogs"
  end

  test "public_show 404 for private collection" do
    get public_collection_path(slug: collections(:private_one).slug)
    assert_response :not_found
  end

  test "manifest serves JSON unauthenticated for unlisted" do
    get collection_manifest_path(slug: collections(:econ).slug)
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "stray-collection", json["format"]
    assert_equal "Economics Blogs", json["collection"]["name"]
  end

  test "manifest 404 for private collection" do
    get collection_manifest_path(slug: collections(:private_one).slug)
    assert_response :not_found
  end

  test "feed serves RSS unauthenticated" do
    get collection_feed_path(slug: collections(:econ).slug)
    assert_response :success
    assert_includes response.body, "<rss"
  end
end
