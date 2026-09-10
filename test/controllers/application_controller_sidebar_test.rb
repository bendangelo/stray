require "test_helper"

class ApplicationControllerSidebarTest < ActionDispatch::IntegrationTest
  test "sidebar unseen counts are set in the controller" do
    sign_in_as users(:one)
    get root_path

    assert_not_nil assigns(:unseen_counts),
           "unseen_counts should be set by the controller before_action"
    assert_kind_of Hash, assigns(:unseen_counts)
  end

  test "unseen_counts is empty when no sources followed" do
    user = users(:one)
    # Remove all follows for this user
    Follow.where(user_id: user.id).destroy_all
    sign_in_as user
    get root_path

    assert_equal({}, assigns(:unseen_counts))
  end

  test "sidebar sources are ordered by follow weight descending, then name" do
    sign_in_as users(:one)
    get root_path

    assert_equal(
      [ sources(:saved_youtube).id, sources(:youtube).id, sources(:bitchute).id ],
      assigns(:sources).map(&:id)
    )
  end
end
