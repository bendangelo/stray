require "test_helper"

class ItemsControllerTest < ActionDispatch::IntegrationTest
  test "updates item state to saved" do
    sign_in_as(users(:one))
    item = items(:video_one)

    patch item_path(item), params: { state: "saved" }, as: :turbo_stream

    assert_response :success
    item.reload
    assert item.saved?
  end

  test "updates item state to hidden" do
    sign_in_as(users(:one))
    item = items(:video_one)

    patch item_path(item), params: { state: "hidden" }, as: :turbo_stream

    assert_response :success
    item.reload
    assert item.hidden?
  end

  test "cannot update other user items" do
    sign_in_as(users(:one))
    item = items(:video_user_two)

    patch item_path(item), params: { state: "saved" }, as: :turbo_stream

    assert_response :not_found
    item.reload
    assert_not item.saved?
  end

  test "rejects invalid state" do
    sign_in_as(users(:one))
    item = items(:video_one)

    patch item_path(item), params: { state: "invalid" }, as: :turbo_stream

    assert_response :bad_request
  end

  test "player returns HTML fragment for valid item" do
    sign_in_as(users(:one))
    item = items(:video_one)

    get player_item_path(item)

    assert_response :success
    assert_includes response.body, "First Video"
    assert_includes response.body, "youtube.com/embed"
  end

  test "player returns 404 for other user items" do
    sign_in_as(users(:one))
    item = items(:video_user_two)

    get player_item_path(item)

    assert_response :not_found
  end

  test "player returns 404 for missing item" do
    sign_in_as(users(:one))

    get player_item_path(id: 99999)

    assert_response :not_found
  end

  test "player requires authentication" do
    item = items(:video_one)

    get player_item_path(item)

    assert_redirected_to new_session_path
  end

  test "saving an item creates a starred interaction and nudges weight up" do
    sign_in_as(users(:one))
    item = items(:video_one)
    follow = follows(:one)
    assert_equal 1.0, follow.weight

    assert_difference -> { Interaction.count }, 1 do
      patch item_path(item), params: { state: "saved" }, as: :turbo_stream
    end

    assert_response :success
    assert Interaction.exists?(user: users(:one), item: item, kind: "starred")
    follow.reload
    assert_in_delta 1.1, follow.weight, 0.001
  end

  test "hiding an item creates a hidden interaction and nudges weight down" do
    sign_in_as(users(:one))
    item = items(:video_one)
    follow = follows(:one)
    assert_equal 1.0, follow.weight

    assert_difference -> { Interaction.count }, 1 do
      patch item_path(item), params: { state: "hidden" }, as: :turbo_stream
    end

    assert_response :success
    assert Interaction.exists?(user: users(:one), item: item, kind: "hidden")
    follow.reload
    assert_in_delta 0.9, follow.weight, 0.001
  end

  test "setting state to unseen creates no interaction" do
    sign_in_as(users(:one))
    item = items(:video_saved)

    assert_no_difference -> { Interaction.count } do
      patch item_path(item), params: { state: "unseen" }, as: :turbo_stream
    end
  end

  test "second save of same item does not nudge weight again" do
    sign_in_as(users(:one))
    item = items(:video_one)
    follow = follows(:one)

    patch item_path(item), params: { state: "saved" }, as: :turbo_stream
    first_weight = follow.reload.weight

    patch item_path(item), params: { state: "unseen" }, as: :turbo_stream
    patch item_path(item), params: { state: "saved" }, as: :turbo_stream
    follow.reload
    assert_equal first_weight, follow.weight
  end
end
