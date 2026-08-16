require "test_helper"

class SourcesControllerTest < ActionDispatch::IntegrationTest
  test "index shows followed active and inactive sources for current user" do
    sign_in_as(users(:one))
    get sources_path

    assert_response :success
    assert_includes response.body, "Test Channel"
    assert_includes response.body, "BC Channel"
    assert_includes response.body, "Dead Channel"
    assert_includes response.body, "Paused"
  end

  test "index with q param filters sources by name" do
    sign_in_as(users(:one))
    get sources_path, params: { q: "Test Channel" }

    assert_response :success
    list = Nokogiri::HTML(response.body).at_css("#sources_list").to_s
    assert_includes list, "Test Channel"
    assert_not_includes list, "BC Channel"
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

  test "new renders add source form" do
    sign_in_as(users(:one))
    get new_source_path

    assert_response :success
    assert_includes response.body, "Add source"
  end

  test "new requires authentication" do
    get new_source_path
    assert_redirected_to new_session_path
  end

  test "create with valid params creates source and follow and enqueues poll job" do
    sign_in_as(users(:one))
    assert_enqueued_with(job: SourcePollJob) do
      post sources_path, params: {
        source: {
          url: "https://example.com/feed.xml",
          kind: "rss_feed",
          name: "My Feed",
          active: "1"
        }
      }
    end

    assert_redirected_to sources_path
    source = Source.find_by(url: "https://example.com/feed.xml")
    assert source
    assert_equal "My Feed", source.name
    assert Follow.exists?(user_id: users(:one).id, source_id: source.id)
  end

  test "create with invalid params re-renders new with errors" do
    sign_in_as(users(:one))
    post sources_path, params: {
      source: {
        url: "",
        kind: "rss_feed"
      }
    }

    assert_response :unprocessable_content
    assert_includes response.body, "can&#39;t be blank"
  end

  test "create with same URL reuses existing source (deterministic external_id)" do
    sign_in_as(users(:one))
    url = "https://example.com/duplicate-feed.xml"

    assert_difference -> { Source.count }, 1 do
      post sources_path, params: {
        source: { url: url, kind: "rss_feed", name: "First Feed", active: "1" }
      }
    end

    first_source = Source.find_by(url: url)
    assert_equal "First Feed", first_source.name

    assert_no_difference -> { Source.count } do
      post sources_path, params: {
        source: { url: url, kind: "rss_feed", name: "Updated Feed", active: "1" }
      }
    end

    first_source.reload
    assert_equal "Updated Feed", first_source.name
  end

  test "create requires authentication" do
    post sources_path, params: { source: { url: "https://example.com", kind: "rss_feed" } }
    assert_redirected_to new_session_path
  end

  test "edit renders edit form for followed source" do
    sign_in_as(users(:one))
    get edit_source_path(sources(:youtube))

    assert_response :success
    assert_includes response.body, "Edit source"
    assert_includes response.body, "Test Channel"
  end

  test "edit returns 404 for source the user does not follow" do
    sign_in_as(users(:two))
    get edit_source_path(sources(:bitchute))
    assert_response :not_found
  end

  test "update with general attributes updates source" do
    sign_in_as(users(:one))
    source = sources(:youtube)

    patch source_path(source), params: {
      source: { name: "Renamed Channel", icon_url: "https://example.com/icon.png" }
    }, as: :turbo_stream

    assert_redirected_to sources_path
    source.reload
    assert_equal "Renamed Channel", source.name
    assert_equal "https://example.com/icon.png", source.icon_url
  end

  test "update pauses source when active set to false" do
    sign_in_as(users(:one))
    source = sources(:youtube)

    patch source_path(source), params: {
      source: { active: "0" }
    }, as: :turbo_stream

    assert_redirected_to sources_path
    source.reload
    assert_not source.active
  end

  test "update unpauses source when active set to true" do
    sign_in_as(users(:one))
    source = sources(:inactive)

    patch source_path(source), params: {
      source: { active: "1" }
    }, as: :turbo_stream

    assert_redirected_to sources_path
    source.reload
    assert source.active
  end

  test "update with reset_weight still works" do
    sign_in_as(users(:one))
    source = sources(:bitchute)
    follow = follows(:two)
    assert_equal 0.5, follow.weight

    patch source_path(source), params: { reset_weight: true }, as: :turbo_stream

    assert_response :success
    follow.reload
    assert_equal 1.0, follow.weight
  end

  test "destroy deletes source and associated follows and items" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    follow_ids = source.follows.pluck(:id)
    item_ids = source.items.pluck(:id)

    assert_difference -> { Source.count } => -1 do
      assert_difference -> { Follow.count } => -follow_ids.size do
        assert_difference -> { Item.count } => -item_ids.size do
          delete source_path(source)
        end
      end
    end

    assert_redirected_to sources_path
    assert_not Source.exists?(source.id)
    follow_ids.each { |id| assert_not Follow.exists?(id) }
    item_ids.each { |id| assert_not Item.exists?(id) }
  end

  test "destroy returns 404 for source the user does not follow" do
    sign_in_as(users(:two))
    delete source_path(sources(:bitchute))
    assert_response :not_found
  end

  test "show with since=1m filters items to last month" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    old_item = source.items.create!(
      user: users(:one), external_id: "old-vid", title: "Old Video",
      url: "https://www.youtube.com/watch?v=old-vid",
      content_text: "old", published_at: 2.months.ago, state: 0
    )

    get source_path(source, since: "1m")

    assert_response :success
    assert_includes response.body, "First Video"
    assert_includes response.body, "Second Video"
    assert_not_includes response.body, "Old Video"
  end

  test "show with since=3m filters items to last 3 months" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    source.items.create!(
      user: users(:one), external_id: "old-vid", title: "Old Video",
      url: "https://www.youtube.com/watch?v=old-vid",
      content_text: "old", published_at: 4.months.ago, state: 0
    )

    get source_path(source, since: "3m")

    assert_response :success
    assert_includes response.body, "First Video"
    assert_not_includes response.body, "Old Video"
  end

  test "show with since=1y filters items to last year" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    source.items.create!(
      user: users(:one), external_id: "old-vid", title: "Old Video",
      url: "https://www.youtube.com/watch?v=old-vid",
      content_text: "old", published_at: 2.years.ago, state: 0
    )

    get source_path(source, since: "1y")

    assert_response :success
    assert_includes response.body, "First Video"
    assert_not_includes response.body, "Old Video"
  end

  test "show with since=all returns all items" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    source.items.create!(
      user: users(:one), external_id: "old-vid", title: "Old Video",
      url: "https://www.youtube.com/watch?v=old-vid",
      content_text: "old", published_at: 2.years.ago, state: 0
    )

    get source_path(source, since: "all")

    assert_response :success
    assert_includes response.body, "First Video"
    assert_includes response.body, "Old Video"
  end

  test "show without since param returns all items" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    source.items.create!(
      user: users(:one), external_id: "old-vid", title: "Old Video",
      url: "https://www.youtube.com/watch?v=old-vid",
      content_text: "old", published_at: 2.years.ago, state: 0
    )

    get source_path(source)

    assert_response :success
    assert_includes response.body, "First Video"
    assert_includes response.body, "Old Video"
  end

  test "show with invalid since value returns all items" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    source.items.create!(
      user: users(:one), external_id: "old-vid", title: "Old Video",
      url: "https://www.youtube.com/watch?v=old-vid",
      content_text: "old", published_at: 2.years.ago, state: 0
    )

    get source_path(source, since: "garbage")

    assert_response :success
    assert_includes response.body, "First Video"
    assert_includes response.body, "Old Video"
    assert_not_includes response.body, "Showing"
  end

  test "show with since filter excludes items with nil published_at" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    source.items.create!(
      user: users(:one), external_id: "no-date", title: "No Date Video",
      url: "https://www.youtube.com/watch?v=no-date",
      content_text: "no date", published_at: nil, state: 0
    )

    get source_path(source, since: "1m")

    assert_response :success
    assert_not_includes response.body, "No Date Video"
  end

  test "show with since=all includes items with nil published_at" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    source.items.create!(
      user: users(:one), external_id: "no-date", title: "No Date Video",
      url: "https://www.youtube.com/watch?v=no-date",
      content_text: "no date", published_at: nil, state: 0
    )

    get source_path(source, since: "all")

    assert_response :success
    assert_includes response.body, "No Date Video"
  end

  test "show assigns total_count regardless of since filter" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    source.items.create!(
      user: users(:one), external_id: "old-vid", title: "Old Video",
      url: "https://www.youtube.com/watch?v=old-vid",
      content_text: "old", published_at: 2.years.ago, state: 0
    )

    get source_path(source, since: "1m")

    assert_response :success
    assert_equal 4, assigns(:total_count)
  end

  test "show renders date filter pills" do
    sign_in_as(users(:one))
    source = sources(:youtube)

    get source_path(source)

    assert_response :success
    assert_includes response.body, "Last month"
    assert_includes response.body, "Last 3 months"
    assert_includes response.body, "Last year"
    assert_includes response.body, "All time"
  end

  test "show renders total item count in header" do
    sign_in_as(users(:one))
    source = sources(:youtube)

    get source_path(source)

    assert_response :success
    assert_includes response.body, "3 items"
  end

  test "show renders showing X of Y when filter is active" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    source.items.create!(
      user: users(:one), external_id: "old-vid", title: "Old Video",
      url: "https://www.youtube.com/watch?v=old-vid",
      content_text: "old", published_at: 2.years.ago, state: 0
    )

    get source_path(source, since: "1m")

    assert_response :success
    assert_includes response.body, "Showing 3 of 4 items"
  end

  test "pull enqueues SourcePollJob and redirects to the source" do
    sign_in_as(users(:one))
    source = sources(:youtube)

    assert_enqueued_with(job: SourcePollJob, args: [ source.id ]) do
      post pull_source_path(source)
    end

    assert_redirected_to source_path(source)
    assert_includes flash[:notice], "Pull started"
  end

  test "pull returns 404 for a source the user does not follow" do
    sign_in_as(users(:two))
    assert_no_enqueued_jobs only: SourcePollJob do
      post pull_source_path(sources(:bitchute))
    end
    assert_response :not_found
  end

  test "pull requires authentication" do
    post pull_source_path(sources(:youtube))
    assert_redirected_to new_session_path
  end

  test "mute sets follow muted and nudges weight down" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    follow = follows(:one)
    assert_equal 1.0, follow.weight
    assert_not follow.muted

    assert_difference -> { Interaction.count }, 1 do
      post mute_source_path(source), as: :turbo_stream
    end

    assert_response :success
    follow.reload
    assert follow.muted
    assert_in_delta 0.7, follow.weight, 0.001
  end

  test "unmute clears follow muted" do
    sign_in_as(users(:one))
    source = sources(:youtube)
    follow = follows(:one)
    follow.update!(muted: true)

    post unmute_source_path(source), as: :turbo_stream

    assert_response :success
    follow.reload
    assert_not follow.muted
  end

  test "mute returns 404 for unfollowed source" do
    sign_in_as(users(:two))
    post mute_source_path(sources(:bitchute)), as: :turbo_stream
    assert_response :not_found
  end

  test "mute requires authentication" do
    post mute_source_path(sources(:youtube))
    assert_redirected_to new_session_path
  end
end
