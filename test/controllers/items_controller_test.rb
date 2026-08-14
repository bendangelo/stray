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
end
