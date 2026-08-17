require "test_helper"

class Stray::Youtube::ChannelResolverTest < ActiveSupport::TestCase
  test "resolves /channel/UC... URL directly without subprocess" do
    result = Stray::Youtube::ChannelResolver.resolve("https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw")

    assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_id
    assert_equal "https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw", result.rss_url
    assert_equal "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_url
    assert_nil result.channel_name
  end

  test "raises for non-YouTube URLs" do
    assert_raises(ArgumentError) do
      Stray::Youtube::ChannelResolver.resolve("https://bitchute.com/channel/abc")
    end
  end

  test "raises for YouTube video URLs" do
    assert_raises(ArgumentError) do
      Stray::Youtube::ChannelResolver.resolve("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    end
  end

  test "resolves /@handle URL via yt-dlp" do
    data = {
      "channel_id" => "UCuAXFkgsw1L7xaCfnd5JJOw",
      "channel" => "Rick Astley",
      "channel_url" => "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw"
    }

    runner = mock_runner(data)
    Stray::YtDlp::Runner.stub(:new, runner) do
      result = Stray::Youtube::ChannelResolver.resolve("https://www.youtube.com/@RickAstley")

      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_id
      assert_equal "https://www.youtube.com/feeds/videos.xml?channel_id=UCuAXFkgsw1L7xaCfnd5JJOw", result.rss_url
      assert_equal "Rick Astley", result.channel_name
      assert_equal "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_url
    end
  end

  test "resolves /c/name URL via yt-dlp" do
    data = {
      "channel_id" => "UCuAXFkgsw1L7xaCfnd5JJOw",
      "channel" => "Rick Astley",
      "channel_url" => "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw"
    }

    runner = mock_runner(data)
    Stray::YtDlp::Runner.stub(:new, runner) do
      result = Stray::Youtube::ChannelResolver.resolve("https://www.youtube.com/c/RickAstley")

      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_id
      assert_equal "Rick Astley", result.channel_name
    end
  end

  test "resolves /user/name URL via yt-dlp" do
    data = {
      "channel_id" => "UCuAXFkgsw1L7xaCfnd5JJOw",
      "channel" => "Rick Astley",
      "channel_url" => "https://www.youtube.com/channel/UCuAXFkgsw1L7xaCfnd5JJOw"
    }

    runner = mock_runner(data)
    Stray::YtDlp::Runner.stub(:new, runner) do
      result = Stray::Youtube::ChannelResolver.resolve("https://www.youtube.com/user/RickAstley")

      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result.channel_id
    end
  end

  test "raises when yt-dlp returns no channel_id" do
    runner = mock_runner(nil)
    Stray::YtDlp::Runner.stub(:new, runner) do
      assert_raises(ArgumentError) do
        Stray::Youtube::ChannelResolver.resolve("https://www.youtube.com/@NoChannel")
      end
    end
  end

  private

  def mock_runner(data)
    runner = Minitest::Mock.new
    runner.expect(:channel_metadata, data, [ String ])
    runner
  end
end
