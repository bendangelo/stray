require "test_helper"

class Stray::Bridges::HelpersTest < ActiveSupport::TestCase
  test "dehumanize parses k/m/b suffixes" do
    assert_equal 1200, Stray::Bridges::Helpers.dehumanize("1.2k")
    assert_equal 3_000_000, Stray::Bridges::Helpers.dehumanize("3m")
    assert_equal 2_000_000_000, Stray::Bridges::Helpers.dehumanize("2b")
  end

  test "dehumanize parses comma numbers and durations" do
    assert_equal 1234, Stray::Bridges::Helpers.dehumanize("1,234")
    assert_equal 3725, Stray::Bridges::Helpers.dehumanize("1:02:05")
    assert_equal 125, Stray::Bridges::Helpers.dehumanize("2:05")
  end

  test "dehumanize parses humanized durations" do
    assert_equal 18_000, Stray::Bridges::Helpers.dehumanize("5 hours")
    assert_equal 172_800, Stray::Bridges::Helpers.dehumanize("2 days")
  end

  test "dehumanize returns integers unchanged" do
    assert_equal 42, Stray::Bridges::Helpers.dehumanize(42)
  end

  test "dehumanize_time parses ISO8601 and humanized" do
    t = Stray::Bridges::Helpers.dehumanize_time("2023-05-22T19:01:43+00:00")
    assert_equal 2023, t.year
  end

  test "find_meta reads meta by property" do
    doc = Nokogiri::HTML('<meta property="og:image" content="https://img/x.jpg">')
    assert_equal "https://img/x.jpg", Stray::Bridges::Helpers.find_meta(doc, "og:image")
  end

  test "find_title returns first non-empty title" do
    doc = Nokogiri::HTML('<html><head><meta property="og:title" content="OG"><title>Title</title></head></html>')
    assert_equal "OG", Stray::Bridges::Helpers.find_title(doc)
  end

  test "absolute_url resolves relative against base" do
    assert_equal "https://host/a/b.jpg",
                 Stray::Bridges::Helpers.absolute_url("/a/b.jpg", base: "https://host")
  end
end
