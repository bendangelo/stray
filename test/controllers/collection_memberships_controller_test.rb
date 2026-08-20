require "test_helper"

class CollectionMembershipsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "create adds source to an existing collection the user owns" do
    source = sources(:inactive)
    collection = collections(:econ)
    assert_difference -> { CollectionMembership.count }, 1 do
      post collection_memberships_path, params: { collection_membership: { source_id: source.id, collection_id: collection.id } }, as: :turbo_stream
    end
    assert_response :success
    assert CollectionMembership.exists?(source: source, collection: collection)
  end

  test "create is idempotent when membership already exists" do
    source = sources(:youtube)
    collection = collections(:econ)
    assert_no_difference -> { CollectionMembership.count } do
      post collection_memberships_path, params: { collection_membership: { source_id: source.id, collection_id: collection.id } }, as: :turbo_stream
    end
    assert_response :success
  end

  test "create returns not_found for a collection the user does not own" do
    other_collection = Collection.create!(user: users(:two), name: "Theirs")
    source = sources(:youtube)
    post collection_memberships_path, params: { collection_membership: { source_id: source.id, collection_id: other_collection.id } }, as: :turbo_stream
    assert_response :not_found
  end

  test "create returns not_found for a source the user does not follow" do
    source = sources(:remote)
    collection = collections(:econ)
    post collection_memberships_path, params: { collection_membership: { source_id: source.id, collection_id: collection.id } }, as: :turbo_stream
    assert_response :not_found
  end

  test "create requires authentication" do
    sign_out
    post collection_memberships_path, params: { collection_membership: { source_id: 1, collection_id: 1 } }, as: :turbo_stream
    assert_redirected_to new_session_path
  end
end
