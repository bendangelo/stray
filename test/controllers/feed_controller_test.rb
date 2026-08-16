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

  test "shows items from followed sources, reverse chronological" do
    sign_in_as(users(:one))
    get root_path

    assert_response :success
    body = response.body
    assert_includes body, "Second Video"
    assert_includes body, "First Video"
    assert_includes body, "Saved Video"
    assert_not_includes body, "Hidden Video"
    assert_not_includes body, "User Two Video"
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

  test "feed orders by effective_time so a boosted weight surfaces older items" do
    sign_in_as(users(:one))
    # video_one (youtube, weight 1.0) published 2.days.ago
    # video_two (youtube, weight 1.0) published 1.day.ago → normally first
    # Give bitchute weight 3.0 (max) so its 3-day-old Saved Video (state 2=saved, not hidden)
    # effective_time = 3.days.ago + (2.0 * 24h) = 1.day.ago
    # Set youtube weight to 0.1 so video_two demotes below video_one
    follows(:one).update!(weight: 0.1)
    follows(:two).update!(weight: 3.0, muted: false)

    get root_path

    assert_response :success
    body = response.body
    # Saved Video (bitchute, weight 3.0, 3d ago → effective 1d ago) should appear before
    # Second Video (youtube, weight 0.1, 1d ago → effective 1d - 21.6h = ~22h ago)
    saved_pos = body.index("Saved Video")
    second_pos = body.index("Second Video")
    assert saved_pos < second_pos, "boosted Saved Video should rank above demoted Second Video"
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
