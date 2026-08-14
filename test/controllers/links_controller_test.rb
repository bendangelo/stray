require "test_helper"

class LinksControllerTest < ActionDispatch::IntegrationTest
  test "enqueues LinkIntakeJob and returns turbo stream" do
    sign_in_as(users(:one))

    assert_enqueued_with(job: LinkIntakeJob, args: [ users(:one).id, "https://youtube.com/@test" ]) do
      post links_path, params: { url: "https://youtube.com/@test" }, as: :turbo_stream
    end

    assert_response :success
    assert_includes response.body, 'id="intake_status"'
    assert_includes response.body, "Checking"
  end

  test "rejects blank url" do
    sign_in_as(users(:one))

    post links_path, params: { url: "" }, as: :turbo_stream

    assert_response :bad_request
  end

  test "requires authentication" do
    post links_path, params: { url: "https://example.com" }, as: :turbo_stream
    assert_redirected_to new_session_path
  end
end
