require "test_helper"
require "ostruct"

class Bridges::PeertubeTest < ActiveSupport::TestCase
  FIXTURE = File.expand_path("../fixtures/files/peertube_videos.json", __dir__)

  def build_page(total:, start:, count:)
    data = JSON.parse(File.read(FIXTURE))
    data["total"] = total
    data["data"] = data["data"].map { |v| v.merge("uuid" => "#{start}-#{v["uuid"]}") }
    OpenStruct.new(status: 200, body: data.to_json)
  end

  test "extract_backfill paginates until limit is reached" do
    page1 = build_page(total: 3, start: 0, count: 1)
    page2 = build_page(total: 3, start: 1, count: 1)
    page3 = build_page(total: 3, start: 2, count: 1)
    pages = [ page1, page1, page2, page3 ]
    requested = []

    core = Stray::Bridges::Peertube.new
    core.define_singleton_method(:fetch) do |url|
      requested << url
      pages.shift
    end
    Stray::Bridges::Peertube.stub(:new, core) do
      @results = Bridges::Peertube.new.extract_backfill("https://tilvids.com/video-channels/fedi", limit: 3)
    end

    assert_equal 3, @results.size
    assert_equal 4, requested.size
    assert_includes requested[2], "start=1"
    assert_includes requested[3], "start=2"
  end

  test "extract_backfill stops at total even when limit is larger" do
    page1 = build_page(total: 2, start: 0, count: 1)
    page2 = build_page(total: 2, start: 1, count: 1)
    pages = [ page1, page1, page2 ]

    core = Stray::Bridges::Peertube.new
    core.define_singleton_method(:fetch) { |_url| pages.shift }
    Stray::Bridges::Peertube.stub(:new, core) do
      @results = Bridges::Peertube.new.extract_backfill("https://tilvids.com/video-channels/fedi", limit: 50)
    end

    assert_equal 2, @results.size
  end

  test "extract_backfill returns empty array when no videos" do
    empty = OpenStruct.new(status: 200, body: { "total" => 0, "data" => [] }.to_json)
    core = Stray::Bridges::Peertube.new
    core.define_singleton_method(:fetch) { |_url| empty }
    Stray::Bridges::Peertube.stub(:new, core) do
      @results = Bridges::Peertube.new.extract_backfill("https://tilvids.com/video-channels/fedi", limit: 50)
    end

    assert_equal [], @results
  end
end
