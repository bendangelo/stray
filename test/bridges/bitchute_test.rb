require "test_helper"
require "ostruct"

class Bridges::BitchuteTest < ActiveSupport::TestCase
  test "extract_backfill maps flat-playlist JSON to ExtractedContent" do
    listing1 = '{"id":"vid1","title":"Video 1","url":"https://www.bitchute.com/channel/Foo//video/vid1","upload_date":"20240101","channel":"Foo","channel_id":"C1","channel_url":"https://www.bitchute.com/channel/Foo","thumbnails":[{"url":"https://img.jpg"}]}'
    listing2 = '{"id":"vid2","title":"Video 2","url":"https://www.bitchute.com/channel/Foo//video/vid2","upload_date":"20240102","channel":"Foo","channel_id":"C1","channel_url":"https://www.bitchute.com/channel/Foo","thumbnails":[{"url":"https://img2.jpg"}]}'
    multi_json = "#{listing1}\n#{listing2}\n"

    runner = Stray::YtDlp::Runner.new
    runner.define_singleton_method(:execute) { |*_args| [ multi_json, "", OpenStruct.new(success?: true) ] }
    Stray::YtDlp::Runner.stub(:new, runner) do
      results = Bridges::Bitchute.new.extract_backfill("https://www.bitchute.com/channel/Foo", limit: 50)

      assert_equal 2, results.size
      first = results.first
      assert_equal "vid1", first.external_id
      assert_equal "https://www.bitchute.com/video/vid1", first.url
      assert_equal "Video 1", first.title
      assert_equal Time.strptime("20240101", "%Y%m%d"), first.published_at
      assert_equal "https://img.jpg", first.thumbnail_url
      assert_equal "Foo", first.creator_identity.name
    end
  end

  test "extract_backfill passes the limit to the runner" do
    captured = nil
    runner = Stray::YtDlp::Runner.new
    runner.define_singleton_method(:execute) { |*args| captured = args; [ "", "", OpenStruct.new(success?: true) ] }
    Stray::YtDlp::Runner.stub(:new, runner) do
      Bridges::Bitchute.new.extract_backfill("https://www.bitchute.com/channel/Foo", limit: 50)
    end
    assert_includes captured, "--playlist-end"
    assert_includes captured, "50"
  end

  test "extract_feed_from_response maps a pre-fetched channel body" do
    core = Minitest::Mock.new
    core.expect(:feed_from_html, [ {
      url: "https://www.bitchute.com/video/v1", title: "V1", external_id: "1", duration: 10,
      published_at: Time.now, thumbnail_url: "https://img.jpg", content_text: nil,
      content_html: nil, tags: [], views: nil, live: nil, is_short: nil,
      creator_identity: { name: nil, url: "https://www.bitchute.com/channel/C1", external_id: "C1", thumbnail_url: nil }
    } ], [ "body", "https://www.bitchute.com/channel/Foo" ])

    response = Struct.new(:status, :body, :headers).new(200, "body", {})

    Stray::Bridges::Bitchute.stub(:new, core) do
      result = Bridges::Bitchute.new.extract_feed_from_response(response, "https://www.bitchute.com/channel/Foo")
      assert_equal 1, result.size
      assert_equal "1", result.first.external_id
    end
  end
end
