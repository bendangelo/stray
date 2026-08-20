require "test_helper"

class Youtube::ChannelResolverTest < ActiveSupport::TestCase
  test "resolves /channel/UC... URL directly without subprocess" do
    result = Youtube::ChannelResolver.resolve("https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw")

    assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_id
    assert_equal "https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw", result.rss_url
    assert_equal "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_url
    assert_nil result.channel_name
  end

  test "raises for non-YouTube URLs" do
    assert_raises(ArgumentError) do
      Youtube::ChannelResolver.resolve("https://bitchute.com/channel/abc")
    end
  end

  test "raises for YouTube video URLs" do
    assert_raises(ArgumentError) do
      Youtube::ChannelResolver.resolve("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    end
  end

  test "resolves /@handle URL via HTML page" do
    stub_channel_page do
      result = Youtube::ChannelResolver.resolve("https://www.youtube.com/@RickAstley")

      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_id
      assert_equal "https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw", result.rss_url
      assert_equal "Rick Astley", result.channel_name
      assert_equal "https://www.youtube.com/@RickAstley", result.channel_url
    end
  end

  test "resolves /c/name URL via HTML page" do
    stub_channel_page do
      result = Youtube::ChannelResolver.resolve("https://www.youtube.com/c/RickAstley")

      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_id
      assert_equal "Rick Astley", result.channel_name
    end
  end

  test "resolves /user/name URL via HTML page" do
    stub_channel_page do
      result = Youtube::ChannelResolver.resolve("https://www.youtube.com/user/RickAstley")

      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_id
    end
  end

  test "raises when channel page HTML has no channel_id and yt-dlp is missing" do
    runner = Minitest::Mock.new
    runner.expect(:channel_metadata, nil) { raise Errno::ENOENT }
    Stray::YtDlp::Runner.stub(:new, runner) do
      stub_channel_page("<html><body>no channel here</body></html>") do
        assert_raises(ArgumentError) do
          Youtube::ChannelResolver.resolve("https://www.youtube.com/@NoChannel")
        end
      end
    end
  end

  test "falls back to yt-dlp when HTML page has no channel_id and yt-dlp is installed" do
    data = {
      "channel_id" => "UCuAXFkgsw1L7xaCfnd5JJOw",
      "channel" => "Rick Astley",
      "channel_url" => "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw"
    }

    runner = mock_runner(data)
    Stray::YtDlp::Runner.stub(:new, runner) do
      stub_channel_page("<html><body>no channel here</body></html>") do
        result = Youtube::ChannelResolver.resolve("https://www.youtube.com/@RickAstley")

        assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_id
      end
    end
  end

  test "skips yt-dlp fallback when binary is missing" do
    runner = Minitest::Mock.new
    runner.expect(:channel_metadata, nil) { raise Errno::ENOENT }
    Stray::YtDlp::Runner.stub(:new, runner) do
      stub_channel_page("<html><body>no channel here</body></html>") do
        assert_raises(ArgumentError) do
          Youtube::ChannelResolver.resolve("https://www.youtube.com/@RickAstley")
        end
      end
    end
  end

  private

  def stub_channel_page(body = nil)
    body ||= File.read(Rails.root.join("test/fixtures/files/youtube_channel_page.html"))
    response = Struct.new(:status, :body).new(200, body)
    client = Minitest::Mock.new
    client.expect(:get, response, [ String ])
    Youtube::ChannelResolver.stub(:http_client, client) do
      yield
    end
  end

  def mock_runner(data)
    runner = Minitest::Mock.new
    runner.expect(:channel_metadata, data, [ String ])
    runner
  end
end
