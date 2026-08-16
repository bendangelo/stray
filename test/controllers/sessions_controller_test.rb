require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email: @user.email, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email: @user.email, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(User.take)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end

  test "orphaned session (user gone) redirects to login and clears the cookie" do
    cookie_value = ActionDispatch::TestRequest.create.cookie_jar.tap do |jar|
      jar.signed[:session_id] = 12345
    end[:session_id]
    cookies["session_id"] = cookie_value

    Session.stub(:find_by, Session.new) do
      get sources_path
    end

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end
end
