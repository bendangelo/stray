require "test_helper"

class SourcesControllerTest < ActionDispatch::IntegrationTest
  test "index shows followed sources for current user" do
    sign_in_as(users(:one))
    get sources_path

    assert_response :success
    assert_includes response.body, "Test Channel"
    assert_includes response.body, "BC Channel"
    assert_not_includes response.body, "Dead Channel"
  end

  test "show displays source items" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    get source_path(source)

    assert_response :success
    assert_includes response.body, "First Video"
    assert_includes response.body, "Second Video"
  end

  test "show displays follow weight" do
    sign_in_as(users(:one))
    source = sources(:bitchute)
    get source_path(source)

    assert_response :success
    assert_includes response.body, "0.5"
  end

  test "show is scoped to followed sources" do
    sign_in_as(users(:one))
    get source_path(sources(:youtube))
    assert_response :success
  end

  test "cannot show a source the user does not follow" do
    sign_in_as(users(:two))
    get source_path(sources(:bitchute))
    assert_response :not_found
  end

  test "reset weight updates follow weight to 1.0" do
    sign_in_as(users(:one))
    source = sources(:bitchute)
    follow = follows(:two)
    assert_equal 0.5, follow.weight

    patch source_path(source), params: { reset_weight: true }, as: :turbo_stream

    assert_response :success
    follow.reload
    assert_equal 1.0, follow.weight
  end

  test "index requires authentication" do
    get sources_path
    assert_redirected_to new_session_path
  end
end
