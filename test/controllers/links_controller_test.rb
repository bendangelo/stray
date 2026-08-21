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
    assert_redirected_to sources_path
  end

  test "create creates a pending source for /channel/UC... URL" do
    sign_in_as(users(:one))
    url = "https://www.youtube.com/channel/UC123"

    post links_path, params: { url: url }

    source = Source.find_by(kind: "youtube_channel", user_id: users(:one).id, url: url)
    assert_not_nil source
    assert source.pending?
    assert_redirected_to sources_path
  end

  test "create creates a pending source for /c/ and /user/ URLs" do
    sign_in_as(users(:one))

    [ "https://www.youtube.com/c/RickAstley", "https://www.youtube.com/user/RickAstley" ].each do |url|
      post links_path, params: { url: url }
      source = Source.find_by(kind: "youtube_channel", user_id: users(:one).id, url: url)
      assert_not_nil source
      assert source.pending?
      assert_redirected_to sources_path
    end
  end

  test "create requires authentication" do
    post links_path, params: { url: "https://www.youtube.com/@handle" }
    assert_redirected_to new_session_path
  end

  test "create auto-subscribes to a manifest URL" do
    sign_in_as(users(:one))
    url = "https://stray.example.com/c/remotetokensecret12345678/manifest.json"

    assert_difference -> { Source.count }, 1 do
      assert_difference -> { Follow.count }, 1 do
        assert_difference -> { RemoteCollection.count }, 1 do
          assert_enqueued_with(job: SourcePollJob) do
            post links_path, params: { url: url }
          end
        end
      end
    end

    source = Source.find_by(kind: :stray_collection, url: url)
    assert_not_nil source
    assert source.active?
    assert_redirected_to source_path(source)
  end

  test "create auto-subscribes to a friendly /c/:slug URL" do
    sign_in_as(users(:one))
    url = "https://stray.example.com/c/remotetokensecret1234567"

    assert_difference -> { Source.count }, 1 do
      assert_enqueued_with(job: SourcePollJob) do
        post links_path, params: { url: url }
      end
    end

    source = Source.find_by(kind: :stray_collection, url: "https://stray.example.com/c/remotetokensecret1234567/manifest.json")
    assert_not_nil source
    assert_redirected_to source_path(source)
  end

  test "create auto-subscribe to an already-subscribed manifest URL redirects to existing source" do
    sign_in_as(users(:one))
    url = "https://stray.example.com/c/remotetokensecret12345678/manifest.json"

    post links_path, params: { url: url }
    source = Source.find_by(kind: :stray_collection, url: url)

    assert_no_difference -> { Source.count } do
      assert_no_difference -> { RemoteCollection.count } do
        assert_no_enqueued_jobs only: SourcePollJob do
          post links_path, params: { url: url }
        end
      end
    end

    assert_redirected_to source_path(source)
  end

  test "create defaults single video URL to follow_channel=false without a prompt" do
    sign_in_as(users(:one))
    url = "https://tilvids.com/w/f6VXVRmGV2GFKcE67Xpv9j"

    assert_enqueued_with(job: LinkIntakeJob, args: [ users(:one).id, url, nil, { follow_channel: false } ]) do
      post links_path, params: { url: url }
    end

    assert_redirected_to sources_path
  end

  test "create enqueues follow_channel job when follow_channel=true is explicitly passed" do
    sign_in_as(users(:one))
    url = "https://tilvids.com/w/f6VXVRmGV2GFKcE67Xpv9j"

    assert_enqueued_with(job: LinkIntakeJob, args: [ users(:one).id, url, nil, { follow_channel: true } ]) do
      post links_path, params: { url: url, follow_channel: "true" }
    end

    assert_redirected_to sources_path
  end

  test "create defaults single YouTube video URL to follow_channel=false without a prompt" do
    sign_in_as(users(:one))
    url = "https://www.youtube.com/watch?v=abc123"

    assert_enqueued_with(job: LinkIntakeJob, args: [ users(:one).id, url, nil, { follow_channel: false } ]) do
      post links_path, params: { url: url }
    end

    assert_redirected_to sources_path
  end

  test "create creates a pending source and enqueues job for a Peertube channel URL" do
    sign_in_as(users(:one))
    url = "https://tube.xy-space.de/a/voxpopuli"

    assert_difference -> { Source.count }, 1 do
      assert_difference -> { Follow.count }, 1 do
        assert_enqueued_with(job: LinkIntakeJob) do
          post links_path, params: { url: url }
        end
      end
    end

    source = Source.find_by(user: users(:one), url: url)
    assert_not_nil source
    assert source.pending?
    assert_equal "peertube_channel", source.kind
    assert Follow.exists?(user: users(:one), source: source)
    assert_redirected_to sources_path
  end

  test "failed extraction marks the pending source as failed with last_error" do
    sign_in_as(users(:one))
    url = "https://tube.debit-space.de/a/voxpopuli"

    post links_path, params: { url: url }

    source = Source.find_by(user: users(:one), url: url)
    assert source.pending?

    failing = Object.new
    failing.define_singleton_method(:extract_feed) { |_url| raise Stray::ExtractionError, "Peertube fetch failed: 404" }
    failing.define_singleton_method(:extract) { |_url| raise Stray::ExtractionError, "Peertube fetch failed: 404" }

    Stray::BridgeRegistry.stub(:find_for_source, failing) do
      LinkIntakeJob.perform_now(users(:one).id, url, source.id)
    end

    source.reload
    assert source.failed?
    assert_equal "Peertube fetch failed: 404", source.last_error
  end

  test "bulk_create auto-subscribes to manifest URLs and queues other links" do
    sign_in_as(users(:one))
    manifest_url = "https://stray.example.com/c/remotetokensecret12345678/manifest.json"
    rss_url = "https://example.com/feed.xml"

    assert_difference -> { Source.where(kind: :stray_collection).count }, 1 do
      assert_enqueued_with(job: LinkIntakeJob) do
        post bulk_create_links_path, params: { urls: "#{manifest_url}\n#{rss_url}" }
      end
    end

    assert_redirected_to sources_path
    assert_includes flash[:notice], "Subscribed to 1 collection"
    assert_includes flash[:notice], "Queued 1 link"
  end
end
