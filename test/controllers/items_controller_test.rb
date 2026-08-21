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

  test "opening player creates an opened interaction" do
    sign_in_as(users(:one))
    item = items(:video_one)

    assert_difference -> { Interaction.count }, 1 do
      get player_item_path(item)
    end

    assert_response :success
    assert Interaction.exists?(user: users(:one), item: item, kind: "opened")
  end

  test "second open of same player does not create a second interaction" do
    sign_in_as(users(:one))
    item = items(:video_one)

    get player_item_path(item)
    assert_difference -> { Interaction.count }, 0 do
      get player_item_path(item)
    end
  end

  test "opening player marks an unseen item as seen" do
    sign_in_as(users(:one))
    item = items(:video_one)
    assert item.unseen?

    get player_item_path(item)

    assert_response :success
    assert item.reload.seen?
  end

  test "opening player does not downgrade a saved item" do
    sign_in_as(users(:one))
    item = items(:video_saved)
    assert item.saved?

    get player_item_path(item)

    assert_response :success
    assert item.reload.saved?
  end

  test "follow_channel enqueues promotion job for a saved_video YouTube item" do
    sign_in_as(users(:one))
    item = items(:video_saved_yt)

    assert_enqueued_with(job: PromoteSavedVideoJob, args: [ item.id ]) do
      post follow_channel_item_path(item)
    end

    assert_redirected_to item_path(item)
    assert_includes flash[:notice], "Following channel"
  end

  test "follow_channel rejects a non-saved_video item" do
    sign_in_as(users(:one))
    item = items(:video_one)

    assert_no_enqueued_jobs only: PromoteSavedVideoJob do
      post follow_channel_item_path(item)
    end

    assert_redirected_to item_path(item)
    assert_includes flash[:alert], "can't follow a channel"
  end

  test "follow_channel rejects a saved_video item that is not a YouTube video" do
    sign_in_as(users(:one))
    source = Source.create!(user: users(:one), kind: :saved_video,
      url: "https://bitchute.com/video/bcvid9", external_id: "bcvid9", name: "BC Saved")
    item = Item.create!(source: source, user: users(:one), external_id: "bcvid9",
      title: "BC Saved", url: "https://bitchute.com/video/bcvid9")

    assert_no_enqueued_jobs only: PromoteSavedVideoJob do
      post follow_channel_item_path(item)
    end

    assert_redirected_to item_path(item)
    assert_includes flash[:alert], "can't follow a channel"
  end

  test "follow_channel returns 404 for other user items" do
    sign_in_as(users(:one))
    item = items(:video_user_two)

    post follow_channel_item_path(item)

    assert_response :not_found
  end

  test "follow_channel requires authentication" do
    item = items(:video_one)

    post follow_channel_item_path(item)

    assert_redirected_to new_session_path
  end
end
