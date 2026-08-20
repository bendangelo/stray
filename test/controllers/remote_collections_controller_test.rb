require "test_helper"

class RemoteCollectionsControllerTest < ActionDispatch::IntegrationTest
  test "destroy deletes source and remote collection" do
    sign_in_as(users(:one))
    assert_difference -> { Source.count }, -1 do
      assert_difference -> { RemoteCollection.count }, -1 do
        delete remote_collection_path, params: { source_id: sources(:remote).id }
      end
    end
    assert_redirected_to sources_path
  end

  test "destroy requires authentication" do
    delete remote_collection_path, params: { source_id: sources(:remote).id }
    assert_redirected_to new_session_path
  end
end
