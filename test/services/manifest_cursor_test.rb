require "test_helper"

class ManifestCursorTest < ActiveSupport::TestCase
  setup do
    @mod = ManifestCursor
  end

  test "decode_offset returns 0 for nil/blank cursor" do
    assert_equal 0, @mod.decode_offset(nil)
    assert_equal 0, @mod.decode_offset("")
  end

  test "decode_offset returns 0 for invalid base64 or json" do
    assert_equal 0, @mod.decode_offset("!!!notbase64!!!")
    assert_equal 0, @mod.decode_offset(Base64.urlsafe_encode64("not json"))
  end

  test "encode_offset then decode_offset round-trips" do
    encoded = @mod.encode_offset(42)
    assert_equal 42, @mod.decode_offset(encoded)
  end

  test "encode_offset emits base64 json with header sc1" do
    decoded = JSON.parse(Base64.urlsafe_decode64(@mod.encode_offset(7)))
    assert_equal "sc1", decoded["h"]
    assert_equal 7, decoded["o"]
  end

  test "next_url builds absolute url with base_url and cursor" do
    url = @mod.next_url(base_url: "https://stray.example.com",
                        path: "/c/slug/manifest.json",
                        cursor: "abc")
    assert_equal "https://stray.example.com/c/slug/manifest.json?cursor=abc", url
  end

  test "next_url builds relative url when base_url is nil" do
    url = @mod.next_url(base_url: nil, path: "/s/slug/manifest.json", cursor: "xyz")
    assert_equal "/s/slug/manifest.json?cursor=xyz", url
  end

  test "next_url returns nil when cursor is nil" do
    assert_nil @mod.next_url(base_url: "https://x", path: "/p", cursor: nil)
  end
end
