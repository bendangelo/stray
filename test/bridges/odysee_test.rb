require "test_helper"

class Bridges::OdyseeTest < ActiveSupport::TestCase
  test "extract_backfill is a no-op (RSS already returns ~50 videos)" do
    assert_nil Bridges::Odysee.new.extract_backfill("https://odysee.com/@samtime:1", limit: 50)
  end
end
