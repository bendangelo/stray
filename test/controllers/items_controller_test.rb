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
end
