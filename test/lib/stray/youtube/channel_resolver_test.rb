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
end
