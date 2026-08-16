require "test_helper"

class TagsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "index lists user tags with counts" do
    get tags_path
    assert_response :success
    assert_includes response.body, "ruby"
    assert_includes response.body, "rails"
  end

  test "index does not show other users tags" do
    Tag.create!(user: users(:two), name: "private")
    get tags_path
    assert_not_includes response.body, "private"
  end

  test "create new tag and enqueue embedding job" do
    assert_enqueued_with(job: EmbeddingJob) do
      post tags_path, params: { tag: { name: "newtag" } }
    end
    assert_redirected_to tags_path
    assert Tag.find_by(user: users(:one), name: "newtag")
  end

  test "create rejects blank name" do
    post tags_path, params: { tag: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "update renames tag and re-enqueues embedding" do
    tag = tags(:ruby)
    assert_enqueued_with(job: EmbeddingJob) do
      patch tag_path(tag), params: { tag: { name: "ruby-lang" } }
    end
    tag.reload
    assert_equal "ruby-lang", tag.name
  end

  test "destroy removes tag and its taggings" do
    tag = tags(:ruby)
    tagging = taggings(:video_one_ruby)
    assert_difference -> { Tag.count } => -1, -> { Tagging.count } => -1 do
      delete tag_path(tag)
    end
    assert_redirected_to tags_path
  end

  test "merge moves taggings to target" do
    source_tag = tags(:ruby)
    target_tag = tags(:rails)
    patch merge_tag_path(source_tag), params: { target_id: target_tag.id }
    assert_redirected_to tags_path
    refute Tag.exists?(source_tag.id)
    assert Tagging.exists?(tag: target_tag, item: items(:video_one))
  end

  test "search returns JSON matches" do
    get search_tags_path, params: { q: "ru" }, as: :json
    assert_response :success
    names = JSON.parse(response.body).map { |t| t["name"] }
    assert_includes names, "ruby"
  end

  test "index requires authentication" do
    sign_out
    get tags_path
    assert_redirected_to new_session_path
  end
end
