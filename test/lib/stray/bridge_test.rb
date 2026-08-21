require "test_helper"

class Stray::BridgeTest < ActiveSupport::TestCase
  class FakeBridge < Stray::Bridge
    def self.matches?(url) = true
    def self.handles_kind?(kind) = true
    def extract(url) = nil
    def extract_feed(url) = []
  end

  test "extract_backfill defaults to nil (unsupported)" do
    assert_nil FakeBridge.new.extract_backfill("https://example.com", limit: 50)
  end
end
