require "test_helper"
require "ostruct"

class Stray::Bridges::BitchuteTest < ActiveSupport::TestCase
  FIXTURE = File.expand_path("../../../fixtures/files/bitchute_channel.html", __dir__)

  def stub_html(body)
    resp = OpenStruct.new(status: 200, body: body)
    extractor = Stray::Bridges::Bitchute.new
    extractor.define_singleton_method(:fetch) { |_url| resp }
    yield extractor
  end

  test "matches? returns true for bitchute URLs" do
    assert Stray::Bridges::Bitchute.matches?("https://www.bitchute.com/channel/Foo")
    assert Stray::Bridges::Bitchute.matches?("https://www.bitchute.com/video/abc123")
  end

  test "matches? returns false for non-bitchute URLs" do
    assert_not Stray::Bridges::Bitchute.matches?("https://example.com")
  end

  test "channel_id and video_id parse paths" do
    assert_equal "Foo", Stray::Bridges::Bitchute.channel_id("https://www.bitchute.com/channel/Foo")
    assert_equal "abc123", Stray::Bridges::Bitchute.video_id("https://www.bitchute.com/video/abc123")
  end

  test "channel_feed parses channel video cards" do
    stub_html(File.read(FIXTURE)) do |extractor|
      items = extractor.channel_feed("https://www.bitchute.com/channel/Foo")
      assert items.any?

      first = items.first
      assert first[:title].present?
      assert first[:external_id].present?
      assert first[:url].start_with?("https://www.bitchute.com/video/")
    end
  end
end
