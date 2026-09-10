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

  test "sidebar sources are capped at 15" do
    user = users(:one)
    15.times do |i|
      source = Source.create!(user: user, kind: :rss_feed,
        url: "https://example.com/feed#{i}.xml", external_id: "cap#{i}",
        name: "Cap Source #{i}")
      Follow.create!(user: user, source: source, weight: 1.0)
    end
    sign_in_as user
    get root_path

    assert_equal 15, assigns(:sources).count
    assert_not_includes assigns(:sources).map(&:name), "BC Channel"
  end

  test "sidebar collections are capped at 10" do
    user = users(:one)
    10.times do |i|
      Collection.create!(user: user, name: "Cap Collection #{i}", visibility: :unlisted)
    end
    sign_in_as user
    get root_path

    assert_equal 10, assigns(:collections).count
    assert_not_includes assigns(:collections).map(&:name), "Private Notes"
  end
end
