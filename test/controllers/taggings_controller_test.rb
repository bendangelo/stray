require "test_helper"

class TaggingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "create attaches existing tag to item" do
    item = items(:video_one)
    tag = tags(:ai)
    post taggings_path, params: { tagging: { item_id: item.id, tag_name: "ai" } }, as: :turbo_stream
    assert_response :success
    assert Tagging.find_by(item: item, tag: tag, source: :user)
  end

  test "create with new tag name creates tag and enqueues embedding" do
    item = items(:video_one)
    assert_enqueued_with(job: EmbeddingJob) do
      post taggings_path, params: { tagging: { item_id: item.id, tag_name: "brandnew" } }, as: :turbo_stream
    end
    assert Tag.find_by(user: users(:one), name: "brandnew")
  end

  test "destroy removes tagging" do
    tagging = taggings(:video_one_ruby)
    delete tagging_path(tagging), as: :turbo_stream
    assert_response :success
    refute Tagging.exists?(tagging.id)
  end

  test "cannot tag another user's item" do
    item = items(:video_user_two)
    post taggings_path, params: { tagging: { item_id: item.id, tag_name: "hack" } }, as: :turbo_stream
    assert_response :not_found
  end

  test "AI-sourced tag chip renders remove button with turbo confirm" do
    tagging = taggings(:video_one_ruby) # source: ai_embedding (0)
    get root_path
    assert_select "form[data-turbo-confirm*='Remove AI-assigned tag']" do
      assert_select "button", text: "×"
    end
  end
end
