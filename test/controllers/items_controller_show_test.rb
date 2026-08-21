require "test_helper"

class ItemsControllerShowTest < ActionDispatch::IntegrationTest
  test "show renders the show template for a valid item" do
    sign_in_as(users(:one))
    item = items(:video_one)

    get item_path(item)

    assert_response :success
    assert_template "items/show"
    assert_includes response.body, "First Video"
  end

  test "show returns 404 for other user items" do
    sign_in_as(users(:one))
    item = items(:video_user_two)

    get item_path(item)

    assert_response :not_found
  end

  test "show returns 404 for missing item" do
    sign_in_as(users(:one))

    get item_path(id: 99999)

    assert_response :not_found
  end

  test "show requires authentication" do
    item = items(:video_one)

    get item_path(item)

    assert_redirected_to new_session_path
  end

  test "show marks an unseen item as seen" do
    sign_in_as(users(:one))
    item = items(:video_one)
    assert item.unseen?

    get item_path(item)

    assert_response :success
    assert item.reload.seen?
  end

  test "show creates an opened interaction" do
    sign_in_as(users(:one))
    item = items(:video_one)

    assert_difference -> { Interaction.count }, 1 do
      get item_path(item)
    end

    assert Interaction.exists?(user: users(:one), item: item, kind: "opened")
  end

  test "second show visit does not create a second interaction" do
    sign_in_as(users(:one))
    item = items(:video_one)

    get item_path(item)
    assert_difference -> { Interaction.count }, 0 do
      get item_path(item)
    end
  end

  test "show does not downgrade a saved item" do
    sign_in_as(users(:one))
    item = items(:video_saved)
    assert item.saved?

    get item_path(item)

    assert_response :success
    assert item.reload.saved?
  end

  test "neighbors from feed context: prev and next in ranking order" do
    sign_in_as(users(:one))
    item = items(:video_two)

    get item_path(item, from: "feed")

    assert_response :success
    # Feed order (follows.weight 1.0 for youtube, so pure published_at DESC):
    # video_three (5h ago) > video_four (6h ago) > video_two (1d ago) > video_one (2d ago) > ...
    # So prev = video_four, next = video_one
    assert_equal "Fourth Video", assigns(:neighbors)[0]&.title
    assert_equal "First Video", assigns(:neighbors)[1]&.title
  end

  test "neighbors from source context: scoped to that source" do
    sign_in_as(users(:one))
    item = items(:video_one)
    source = sources(:youtube)

    get item_path(item, from: "source", source_id: source.id)

    assert_response :success
    # All youtube items belong to user one; neighbors must be youtube items
    neighbors = assigns(:neighbors).compact
    neighbors.each do |n|
      assert_equal source.id, n.source_id
    end
  end

  test "neighbors are nil when item not in scope (e.g. hidden)" do
    sign_in_as(users(:one))
    item = items(:video_hidden)

    get item_path(item, from: "feed")

    assert_response :success
    assert_equal [ nil, nil ], assigns(:neighbors)
  end

  test "neighbors from feed context with q filter respects the search" do
    sign_in_as(users(:one))
    item = items(:video_one)

    get item_path(item, from: "feed", q: "Ruby")

    assert_response :success
    neighbors = assigns(:neighbors).compact
    neighbors.each do |n|
      # only items matching "Ruby" can be neighbors
      assert n.content_text.to_s.match?(/Ruby/i) || n.title.to_s.match?(/Ruby/i)
    end
  end
end
