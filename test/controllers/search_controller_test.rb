require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  test "redirects to login when not authenticated" do
    get search_suggest_path(q: "ruby")
    assert_redirected_to new_session_path
  end

  test "returns HTML suggestions for valid query" do
    sign_in_as(users(:one))
    rebuild_full_search_index(Item)
    get search_suggest_path(q: "first")
    assert_response :success
    assert_includes response.body, "<mark>First</mark> Video"
    assert_includes response.body, "<mark>"
  end

  test "returns empty list for query under 3 chars" do
    sign_in_as(users(:one))
    get search_suggest_path(q: "fi")
    assert_response :success
    assert_not_includes response.body, '<li role="option"'
  end

  test "returns source suggestions linking to the source" do
    sign_in_as(users(:one))
    get search_suggest_path(q: "Test Channel")
    assert_response :success
    assert_includes response.body, "Test Channel"
    assert_includes response.body, "/sources/#{sources(:youtube).id}"
  end

  test "search input and results expose combobox and listbox roles" do
    sign_in_as(users(:one))
    get root_path
    assert_response :success
    assert_select "input[role='combobox'][aria-autocomplete='list'][aria-controls='search-suggestions']"
    assert_select "ul#search-suggestions[role='listbox']"
  end

  test "returns no suggestions for no matches" do
    sign_in_as(users(:one))
    rebuild_full_search_index(Item)
    get search_suggest_path(q: "zzzzzzz")
    assert_response :success
    assert_includes response.body, "No suggestions"
  end

  test "does not return hidden items" do
    sign_in_as(users(:one))
    rebuild_full_search_index(Item)
    get search_suggest_path(q: "hidden")
    assert_response :success
    assert_not_includes response.body, "Hidden Video"
  end

  test "does not return other users items" do
    sign_in_as(users(:one))
    rebuild_full_search_index(Item)
    get search_suggest_path(q: "user two")
    assert_response :success
    assert_not_includes response.body, "User Two Video"
  end

  test "handles special characters without 500" do
    sign_in_as(users(:one))
    get search_suggest_path(q: '"')
    assert_response :success
  end
end
