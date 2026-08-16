require "test_helper"

class LinksControllerTest < ActionDispatch::IntegrationTest
  test "enqueues LinkIntakeJob and redirects to source page for channel URL" do
    user = users(:one)
    sign_in_as(user)

    post links_path, params: { url: "https://www.youtube.com/channel/UCtest123" }

    source = Source.find_by(external_id: "UCtest123", user_id: user.id)
    assert_not_nil source
    assert_equal "youtube_channel", source.kind
    assert_enqueued_with(job: LinkIntakeJob, args: [ user.id, "https://www.youtube.com/channel/UCtest123", source.id ])
    assert_redirected_to source_path(source)
  end

  test "enqueues LinkIntakeJob and redirects for youtube video URL" do
    user = users(:one)
    sign_in_as(user)

    post links_path, params: { url: "https://youtu.be/vid123" }

    assert_enqueued_with(job: LinkIntakeJob, args: [ user.id, "https://youtu.be/vid123" ])
    assert_redirected_to root_path
  end

  test "enqueues LinkIntakeJob and redirects to sources for handle URL" do
    user = users(:one)
    sign_in_as(user)

    post links_path, params: { url: "https://www.youtube.com/@handle" }

    assert_enqueued_with(job: LinkIntakeJob, args: [ user.id, "https://www.youtube.com/@handle" ])
    assert_redirected_to sources_path
  end

  test "redirects manifest URL to remote collection preview" do
    user = users(:one)
    sign_in_as(user)

    post links_path, params: { url: "https://stray.example.com/c/abcdefghijklmnopqrstuvwx/manifest.json" }

    assert_redirected_to new_remote_collection_path(manifest_url: "https://stray.example.com/c/abcdefghijklmnopqrstuvwx/manifest.json")
  end

  test "redirects friendly /c/:slug URL to remote collection preview" do
    user = users(:one)
    sign_in_as(user)

    post links_path, params: { url: "https://stray.example.com/c/abcdefghijklmnopqrstuvwx" }

    assert_redirected_to new_remote_collection_path(manifest_url: "https://stray.example.com/c/abcdefghijklmnopqrstuvwx/manifest.json")
  end

  test "rejects blank url" do
    sign_in_as(users(:one))

    post links_path, params: { url: "" }

    assert_redirected_to root_path
  end

  test "requires authentication" do
    post links_path, params: { url: "https://example.com" }
    assert_redirected_to new_session_path
  end

  test "bulk_create enqueues one job per URL and redirects to sources" do
    user = users(:one)
    sign_in_as(user)

    post bulk_create_links_path, params: {
      urls: "https://youtu.be/aaa\nhttps://youtu.be/bbb\nhttps://youtu.be/ccc\n"
    }

    assert_equal 3, enqueued_jobs.select { |j| j[:job] == LinkIntakeJob }.size
    assert_redirected_to sources_path
  end

  test "bulk_create dedupes duplicate URLs" do
    user = users(:one)
    sign_in_as(user)

    post bulk_create_links_path, params: {
      urls: "https://youtu.be/aaa\nhttps://youtu.be/aaa\nhttps://youtu.be/aaa\n"
    }

    assert_equal 1, enqueued_jobs.select { |j| j[:job] == LinkIntakeJob }.size
    assert_redirected_to sources_path
  end

  test "bulk_create redirects to preview when manifest URL present" do
    sign_in_as(users(:one))

    post bulk_create_links_path, params: {
      urls: "https://stray.example.com/c/abcdefghijklmnopqrstuvwx/manifest.json\n"
    }

    assert_redirected_to new_remote_collection_path(manifest_url: "https://stray.example.com/c/abcdefghijklmnopqrstuvwx/manifest.json")
  end

  test "bulk_create rejects empty input" do
    sign_in_as(users(:one))

    post bulk_create_links_path, params: { urls: "   \n  \n" }

    assert_redirected_to sources_path
    assert_equal "No URLs provided.", flash[:alert]
  end
end
