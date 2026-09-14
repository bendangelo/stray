require "test_helper"

class FeedControllerTest < ActionDispatch::IntegrationTest
  test "redirects to login when not authenticated" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "shows feed for authenticated user" do
    sign_in_as(users(:one))
    get root_path
    assert_response :success
    assert_select "title", "Feed | Stray"
  end

  test "browse shows unseen items from followed sources" do
    sign_in_as(users(:one))
    get root_path

    assert_response :success
    body = response.body
    assert_includes body, "Second Video"
    assert_includes body, "First Video"
    assert_not_includes body, "Saved Video"
    assert_not_includes body, "Hidden Video"
    assert_not_includes body, "User Two Video"
  end

  test "browse excludes seen items" do
    sign_in_as(users(:one))
    items(:video_one).update!(state: :seen)
    get root_path

    assert_response :success
    assert_not_includes response.body, "First Video"
  end

  test "search filters by FTS5 query" do
    sign_in_as(users(:one))
    get root_path, params: { q: "Ruby" }

    assert_response :success
    assert_includes response.body, "First Video"
    assert_not_includes response.body, "Second Video"
  end

  test "search with no results shows empty message" do
    sign_in_as(users(:one))
    get root_path, params: { q: "nonexistent" }

    assert_response :success
    assert_includes response.body, "No results"
  end

  test "tag filter shows only items with that tag" do
    sign_in_as(users(:one))
    get root_path, params: { tag: "ruby" }

    assert_response :success
    assert_includes response.body, "First Video"
    assert_not_includes response.body, "Second Video"
  end

  test "tag filter combined with search" do
    sign_in_as(users(:one))
    get root_path, params: { q: "Ruby", tag: "ruby" }

    assert_response :success
    assert_includes response.body, "First Video"
  end

  test "assigns tags collection for tag bar" do
    sign_in_as(users(:one))
    get root_path

    assert_response :success
    assert_not_nil assigns(:tags)
  end

  test "tag bar includes tag names" do
    sign_in_as(users(:one))
    get root_path

    assert_response :success
    assert_includes response.body, "ruby"
    assert_includes response.body, "rails"
    assert_includes response.body, "ai"
  end

  test "browse interleaves items across sources instead of grouping by source" do
    sign_in_as(users(:one))
    yt = sources(:youtube)
    bc = sources(:bitchute)
    follows(:one).update!(weight: 1.0)
    follows(:two).update!(weight: 1.0)

    %w[MixA1 MixA2 MixA3].each_with_index do |title, i|
      Item.create!(source: yt, user: users(:one), external_id: "mix-a-#{i}", title: title,
        url: "https://example.com/mix-a-#{i}", content_text: "x",
        published_at: (i + 1).hours.ago, state: :unseen)
    end
    %w[MixB1 MixB2 MixB3].each_with_index do |title, i|
      Item.create!(source: bc, user: users(:one), external_id: "mix-b-#{i}", title: title,
        url: "https://example.com/mix-b-#{i}", content_text: "x",
        published_at: (i + 1).hours.ago + 30.minutes, state: :unseen)
    end

    get root_path

    assert_response :success
    body = response.body
    order = %w[MixB1 MixA1 MixB2 MixA2 MixB3 MixA3]
    positions = order.sort_by { |title| body.index(title) }
    assert_equal order, positions, "expected alternating sources, got #{positions.inspect}"
  end

  test "saved mode shows saved items only, chronologically" do
    sign_in_as(users(:one))
    get root_path, params: { saved: "1" }

    assert_response :success
    assert_includes response.body, "Saved Video"
    assert_not_includes response.body, "First Video"
  end

  test "saved mode includes muted sources" do
    sign_in_as(users(:one))
    follows(:one).update!(muted: true)
    items(:video_one).update!(state: :saved)

    get root_path, params: { saved: "1" }

    assert_response :success
    assert_includes response.body, "First Video"
  end

  test "filtered search includes seen items and is chronological" do
    sign_in_as(users(:one))
    items(:video_one).update!(state: :seen)

    get root_path, params: { q: "Ruby" }

    assert_response :success
    assert_includes response.body, "First Video"
  end

  test "browse shows caught up state when nothing is unseen" do
    sign_in_as(users(:one))
    Item.where(user: users(:one)).update_all(state: Item.states[:seen])

    get root_path

    assert_response :success
    assert_includes response.body, "all caught up"
  end

  test "browse renders the mix explanation" do
    sign_in_as(users(:one))
    get root_path

    assert_response :success
    assert_includes response.body, "mixed to spread channels"
  end

  test "sidebar has a saved link" do
    sign_in_as(users(:one))
    get root_path

    assert_response :success
    assert_select "a[href='#{root_path(saved: 1)}']"
  end

  test "feed excludes items from muted sources by default" do
    sign_in_as(users(:one))
    follows(:one).update!(muted: true)

    get root_path

    assert_response :success
    assert_not_includes response.body, "First Video"
    assert_not_includes response.body, "Second Video"
  end

  test "feed includes muted sources when show_muted=1" do
    sign_in_as(users(:one))
    follows(:one).update!(muted: true)

    get root_path, params: { show_muted: "1" }

    assert_response :success
    assert_includes response.body, "First Video"
  end

  test "feed assigns muted_count" do
    sign_in_as(users(:one))
    follows(:one).update!(muted: true)

    get root_path

    assert_response :success
    assert_equal 1, assigns(:muted_count)
  end

  test "feed with no muted sources does not show muted toggle" do
    sign_in_as(users(:one))
    get root_path

    assert_response :success
    assert_not_includes response.body, "muted"
  end
end
