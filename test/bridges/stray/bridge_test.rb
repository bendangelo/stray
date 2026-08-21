require "test_helper"

class Stray::BridgeTest < ActiveSupport::TestCase
  test "default trust_level is :scraped_html" do
    assert_equal :scraped_html, Stray::Bridge.trust_level
  end

  test "default requires_auth? is false" do
    assert_not Stray::Bridge.requires_auth?
  end

  test "default secret_fields is empty array" do
    assert_equal [], Stray::Bridge.secret_fields
  end

  test "default license is AGPL-3.0" do
    assert_equal "AGPL-3.0", Stray::Bridge.license
  end

  test "default metadata fields are nil" do
    assert_nil Stray::Bridge.site_homepage
    assert_nil Stray::Bridge.last_tested_against
    assert_nil Stray::Bridge.author
    assert_nil Stray::Bridge.source_url
  end

  test "runtime interface raises NotImplementedError" do
    assert_raises(NotImplementedError) { Stray::Bridge.matches?("x") }
    bridge = Stray::Bridge.new
    assert_raises(NotImplementedError) { bridge.extract("x") }
    assert_raises(NotImplementedError) { bridge.extract_feed("x") }
  end

  test "enrich_tags defaults to nil" do
    assert_nil Stray::Bridge.new.enrich_tags("x")
  end

  test "handles_kind? defaults to false" do
    assert_not Stray::Bridge.handles_kind?("anything")
  end
end
