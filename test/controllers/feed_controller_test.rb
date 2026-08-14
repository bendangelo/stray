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
    assert_select "title", "Stray"
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
end
