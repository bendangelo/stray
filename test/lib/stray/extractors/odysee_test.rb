require "test_helper"
require "ostruct"

class Stray::Extractors::OdyseeTest < ActiveSupport::TestCase
  FIXTURE = File.expand_path("../../../fixtures/files/odysee_rss.xml", __dir__)

  def stub_feed(body)
    resp = OpenStruct.new(status: 200, body: body)
    extractor = Stray::Extractors::Odysee.new
    extractor.define_singleton_method(:fetch) { |_url| resp }
    yield extractor
  end

  test "matches? returns true for odysee URLs" do
    assert Stray::Extractors::Odysee.matches?("https://odysee.com/@samtime:1")
  end

  test "matches? returns false for non-odysee URLs" do
    assert_not Stray::Extractors::Odysee.matches?("https://example.com")
  end

  test "channel_handle parses @handle:id" do
    assert_equal "samtime:1", Stray::Extractors::Odysee.channel_handle("https://odysee.com/@samtime:1")
  end

  test "rss_url builds the feed URL" do
    assert_equal "https://odysee.com/$/rss/@samtime:1",
                 Stray::Extractors::Odysee.rss_url("https://odysee.com/@samtime:1")
  end

  test "channel_feed parses RSS entries" do
    stub_feed(File.read(FIXTURE)) do |extractor|
      items = extractor.channel_feed("https://odysee.com/@samtime:1")
      assert items.any?

      first = items.first
      assert_equal "https://odysee.com/apple-reacts-to-the-new-framework-laptop:f0bfe667ed0eb53f55aa9ba6fea16d827ec9b43d", first[:url]
      assert first[:title].present?
      assert first[:published_at].is_a?(Time)
      assert first[:external_id].present?
      assert_equal "SAMTIME on Odysee", first[:creator_identity][:name]
    end
  end

  test "channel_feed raises for non-channel URL" do
    assert_raises(Stray::ExtractionError) do
      Stray::Extractors::Odysee.new.channel_feed("https://odysee.com/some-video")
    end
  end
end
