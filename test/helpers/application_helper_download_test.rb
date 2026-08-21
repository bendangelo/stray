require "test_helper"

class ApplicationHelperDownloadTest < ActionView::TestCase
  include ApplicationHelper

  test "yt_dlp_download_command returns the fixed format command with the item URL" do
    item = items(:video_one)
    assert_equal %(yt-dlp -f "bv*+ba/b" "#{item.url}"), yt_dlp_download_command(item)
  end

  test "yt_dlp_download_command double-quotes the URL" do
    item = Item.new(url: "https://www.youtube.com/watch?v=vid1")
    assert_equal %(yt-dlp -f "bv*+ba/b" "https://www.youtube.com/watch?v=vid1"), yt_dlp_download_command(item)
  end

  test "context_params_for on a feed request infers from=feed and forwards q/tag/show_muted" do
    item = items(:video_one)
    request.path = root_path
    request.query_parameters[:q] = "Ruby"
    request.query_parameters[:tag] = "ruby"

    params = context_params_for(item)
    assert_equal "feed", params[:from]
    assert_equal "Ruby", params[:q]
    assert_equal "ruby", params[:tag]
  end

  test "context_params_for on a source show request infers from=source with source_id" do
    item = items(:video_one)
    request.path = source_path(item.source)
    request.query_parameters.clear

    params = context_params_for(item)
    assert_equal "source", params[:from]
    assert_equal item.source_id, params[:source_id]
  end

  test "context_params_for forwards an explicit from param when present" do
    item = items(:video_one)
    request.path = item_path(item)
    request.query_parameters[:from] = "source"
    request.query_parameters[:source_id] = item.source_id.to_s

    params = context_params_for(item)
    assert_equal "source", params[:from]
    assert_equal item.source_id, params[:source_id].to_i
  end

  test "back_to_feed_path returns root_path with feed context params" do
    item = items(:video_one)
    request.path = item_path(item)
    request.query_parameters[:from] = "feed"
    request.query_parameters[:q] = "Ruby"

    path = back_to_feed_path
    assert_match %r{^/\?}, path
    assert_includes path, "q=Ruby"
  end

  test "back_to_feed_path returns source_path for from=source" do
    item = items(:video_one)
    request.path = item_path(item)
    request.query_parameters[:from] = "source"
    request.query_parameters[:source_id] = item.source_id.to_s

    path = back_to_feed_path
    assert_match %r{^/sources/#{item.source_id}}, path
  end

  test "back_to_feed_path returns collection_path for from=collection" do
    item = items(:video_one)
    collection = collections(:econ)
    request.path = item_path(item)
    request.query_parameters[:from] = "collection"
    request.query_parameters[:collection_id] = collection.id.to_s

    path = back_to_feed_path
    assert_match %r{^/collections/#{collection.id}}, path
  end
end
