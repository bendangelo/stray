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
end
