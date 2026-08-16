require "test_helper"

class RemoteCollectionsControllerTest < ActionDispatch::IntegrationTest
  test "new renders form with manifest_url field" do
    sign_in_as(users(:one))
    get new_remote_collection_path
    assert_response :success
    assert_includes response.body, "manifest_url"
  end

  test "new requires authentication" do
    get new_remote_collection_path
    assert_redirected_to new_session_path
  end

  test "create fetches manifest and renders preview" do
    sign_in_as(users(:one))
    VCR.use_cassette("remote_collection/manifest_first_page") do
      post remote_collection_path, params: { remote_collection: { manifest_url: "https://stray.example.com/c/abc/manifest.json" } }
    end
    assert_response :success
    assert_includes response.body, "Econ"
    assert_includes response.body, "Subscribe"
  end

  test "create rejects blocked URL" do
    sign_in_as(users(:one))
    post remote_collection_path, params: { remote_collection: { manifest_url: "http://localhost:3000/c/abc/manifest.json" } }
    assert_response :unprocessable_content
    assert_includes response.body, "blocked"
  end

  test "create with invalid manifest returns error" do
    sign_in_as(users(:one))
    VCR.use_cassette("remote_collection/manifest_empty") do
      post remote_collection_path, params: { remote_collection: { manifest_url: "https://stray.example.com/c/none/manifest.json" } }
    end
    assert_response :unprocessable_content
  end

  test "subscribe creates Source + Follow + RemoteCollection and enqueues poll" do
    sign_in_as(users(:one))
    assert_difference -> { Source.count }, 1 do
      assert_difference -> { Follow.count }, 1 do
        assert_difference -> { RemoteCollection.count }, 1 do
          assert_enqueued_with(job: SourcePollJob) do
            post subscribe_remote_collection_path, params: {
              remote_collection: {
                manifest_url: "https://stray.example.com/c/abc/manifest.json",
                collection_name: "Econ",
                producer_instance_name: "Alice"
              }
            }
          end
        end
      end
    end
    source = Source.find_by(kind: :stray_collection, url: "https://stray.example.com/c/abc/manifest.json")
    assert_redirected_to source_path(source)
  end

  test "subscribe rejects duplicate (same user + manifest_url)" do
    sign_in_as(users(:one))
    assert_no_difference -> { Source.count } do
      post subscribe_remote_collection_path, params: {
        remote_collection: { manifest_url: sources(:remote).url, collection_name: "X" }
      }
    end
    assert_redirected_to source_path(sources(:remote))
  end

  test "subscribe requires authentication" do
    post subscribe_remote_collection_path, params: { remote_collection: { manifest_url: "https://x" } }
    assert_redirected_to new_session_path
  end

  test "destroy deletes source and remote collection" do
    sign_in_as(users(:one))
    assert_difference -> { Source.count }, -1 do
      assert_difference -> { RemoteCollection.count }, -1 do
        delete remote_collection_path, params: { source_id: sources(:remote).id }
      end
    end
    assert_redirected_to sources_path
  end
end
