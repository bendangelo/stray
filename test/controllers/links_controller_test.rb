require "test_helper"

class LinksControllerTest < ActionDispatch::IntegrationTest
  test "create creates a pending source and follow for a /@handle URL and enqueues job" do
    sign_in_as(users(:one))
    url = "https://www.youtube.com/@StreetOfSilence"

    assert_enqueued_with(job: LinkIntakeJob) do
      post links_path, params: { url: url }
    end

    source = Source.find_by(kind: "youtube_channel", user_id: users(:one).id, url: url)
    assert_not_nil source
    assert source.pending?
    assert Follow.exists?(user: users(:one), source: source)
    assert_redirected_to source_path(source)
  end

  test "create creates a pending source for /channel/UC... URL" do
    sign_in_as(users(:one))
    url = "https://www.youtube.com/channel/UC123"

    post links_path, params: { url: url }

    source = Source.find_by(kind: "youtube_channel", user_id: users(:one).id, url: url)
    assert_not_nil source
    assert source.pending?
    assert_redirected_to source_path(source)
  end

  test "create creates a pending source for /c/ and /user/ URLs" do
    sign_in_as(users(:one))

    [ "https://www.youtube.com/c/RickAstley", "https://www.youtube.com/user/RickAstley" ].each do |url|
      post links_path, params: { url: url }
      source = Source.find_by(kind: "youtube_channel", user_id: users(:one).id, url: url)
      assert_not_nil source
      assert source.pending?
      assert_redirected_to source_path(source)
    end
  end

  test "create requires authentication" do
    post links_path, params: { url: "https://www.youtube.com/@handle" }
    assert_redirected_to new_session_path
  end
end
