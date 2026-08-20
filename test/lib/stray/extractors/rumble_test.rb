require "test_helper"
require "ostruct"

class Stray::Extractors::RumbleTest < ActiveSupport::TestCase
  FIXTURE = File.expand_path("../../../fixtures/files/rumble_channel.html", __dir__)

  def stub_html(body)
    resp = OpenStruct.new(status: 200, body: body)
    extractor = Stray::Extractors::Rumble.new
    extractor.define_singleton_method(:fetch) { |_url| resp }
    yield extractor
  end

  test "matches? returns true for rumble URLs" do
    assert Stray::Extractors::Rumble.matches?("https://rumble.com/c/BrightInsight")
    assert Stray::Extractors::Rumble.matches?("https://rumble.com/v7a8neu.html")
  end

  test "matches? returns false for non-rumble URLs" do
    assert_not Stray::Extractors::Rumble.matches?("https://example.com")
  end

  test "channel_slug parses /c/ and /user/ URLs" do
    assert_equal "BrightInsight", Stray::Extractors::Rumble.channel_slug("https://rumble.com/c/BrightInsight")
    assert_equal "samtime", Stray::Extractors::Rumble.channel_slug("https://rumble.com/user/samtime")
  end

  test "channel_feed parses the embedded rum-videos-grid JSON" do
    body = File.read(FIXTURE)
    stub_html(body) do |extractor|
      items = extractor.channel_feed("https://rumble.com/c/BrightInsight")
      assert_equal 3, items.size

      first = items.first
      assert_equal "https://rumble.com/v7a8neu-what-you-need-to-know-about-second-great-sphinx-buried-under-giza.html", first[:url]
      assert_equal "436792702", first[:external_id]
      assert_equal 1046, first[:duration]
      assert_equal 2026, first[:published_at].year
      assert_equal 15335, first[:views]
      assert_equal false, first[:live]
      assert_equal false, first[:is_short]
      assert_equal [ "bright insight", "jimmy corsetti", "second sphinx" ], first[:tags]
      assert_equal "Bright Insight", first[:creator_identity][:name]
      assert_equal "https://rumble.com/c/BrightInsight", first[:creator_identity][:url]
    end
  end

  test "channel_feed raises when rum-videos-grid missing" do
    stub_html("<html><body>no grid</body></html>") do |extractor|
      assert_raises(Stray::ExtractionError) do
        extractor.channel_feed("https://rumble.com/c/BrightInsight")
      end
    end
  end
end
