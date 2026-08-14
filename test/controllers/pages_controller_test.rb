require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "GET about renders homepage with logo" do
    get about_path

    assert_response :success
    assert_select "img[alt=?]", "Stray Logo"
  end

  test "GET privacy_and_terms renders successfully" do
    get privacy_and_terms_path

    assert_response :success
  end
end
