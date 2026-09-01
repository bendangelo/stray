require "test_helper"

class Bridges::OdyseeTest < ActiveSupport::TestCase
  test "extract_backfill is a no-op (RSS already returns ~50 videos)" do
    assert_nil Bridges::Odysee.new.extract_backfill("https://odysee.com/@samtime:1", limit: 50)
  end

  test "extract_feed_from_response maps a pre-fetched RSS body" do
    core = Minitest::Mock.new
    core.expect(:feed_from_rss, [ {
      url: "https://odysee.com/v1", title: "V1", external_id: "1", duration: 10,
      published_at: Time.now, thumbnail_url: "https://img.jpg", content_text: nil,
      content_html: nil, tags: [], views: nil, live: nil, is_short: nil,
      creator_identity: { name: "Chan", url: "https://odysee.com/@c:1", external_id: "c:1", thumbnail_url: nil }
    } ], [ "body", "https://odysee.com/@c:1" ])

    response = Struct.new(:status, :body, :headers).new(200, "body", {})

    Stray::Bridges::Odysee.stub(:new, core) do
      result = Bridges::Odysee.new.extract_feed_from_response(response, "https://odysee.com/@c:1")
      assert_equal 1, result.size
      assert_equal "1", result.first.external_id
    end
  end
end
