require "test_helper"

class CollectionSyncFlowTest < ActionDispatch::IntegrationTest
  def setup
    @user = users(:one)
    @collection = collections(:econ)
    @source = sources(:youtube)
    @item = @source.items.create!(
      user: @user, external_id: "relay-item-1", title: "Relayed Video",
      url: "https://example.com/watch?v=relay1", content_text: "relayed content",
      published_at: 1.day.ago, state: 0
    )
    tag = Tag.create!(user: @user, name: "relay-tag")
    Tagging.create!(item: @item, tag: tag, source: :user)
  end

  test "producer serves manifest with items and tags" do
    get collection_manifest_path(slug: @collection.slug)
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "stray-collection", json["format"]
    assert_equal "Economics Blogs", json.dig("collection", "name")
    item = json["items"].find { |i| i["external_id"] == "relay-item-1" }
    assert_equal "Relayed Video", item["title"]
    assert_equal "relayed content", item["content_text"]
    assert_includes item["tags"], "relay-tag"
    assert_not item.key?("summary")
    assert_not item.key?("embedding")
    assert_not item.key?("state")
  end

  test "consumer subscribes, syncs, and items appear in feed with tags" do
    sign_in_as(@user)
    manifest_url = "https://stray.example.com/c/remotetokensecret12345678/manifest.json"

    VCR.use_cassette("remote_collection/integration_manifest", allow_playback_repeats: true) do
      assert_difference -> { Source.where(kind: :stray_collection).count }, 1 do
        assert_enqueued_with(job: SourcePollJob) do
          post links_path, params: { url: manifest_url }
        end
      end

      perform_enqueued_jobs(only: SourcePollJob)
    end

    source = Source.find_by(kind: :stray_collection, url: manifest_url)
    assert_redirected_to source_path(source)

    assert source.items.exists?(external_id: "relay-item-1", title: "Relayed Video")
    relayed = source.items.find_by(external_id: "relay-item-1")
    assert Tagging.exists?(item: relayed, tag: Tag.find_by(user: @user, name: "relay-tag"), source: :user)

    get root_path
    assert_includes response.body, "Relayed Video"

    get root_path(tag: "relay-tag")
    assert_includes response.body, "Relayed Video"
  end
end
