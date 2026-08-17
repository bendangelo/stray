require "test_helper"

class UrlGuardTest < ActiveSupport::TestCase
  test "allows public https URLs" do
    assert UrlGuard.allowed?("https://stray.example.com/c/abc/manifest.json")
  end

  test "allows public http URLs" do
    assert UrlGuard.allowed?("http://stray.example.com/c/abc/manifest.json")
  end

  test "rejects localhost" do
    assert_not UrlGuard.allowed?("http://localhost:3000/c/abc/manifest.json")
    assert_not UrlGuard.allowed?("http://127.0.0.1:3000/c/abc/manifest.json")
  end

  test "rejects IPv6 loopback" do
    assert_not UrlGuard.allowed?("http://[::1]/c/abc/manifest.json")
  end

  test "rejects private 10.x" do
    assert_not UrlGuard.allowed?("http://10.0.0.1/c/abc/manifest.json")
  end

  test "rejects private 172.16-31.x" do
    assert_not UrlGuard.allowed?("http://172.16.0.1/c/abc/manifest.json")
    assert_not UrlGuard.allowed?("http://172.31.255.254/c/abc/manifest.json")
  end

  test "rejects private 192.168.x" do
    assert_not UrlGuard.allowed?("http://192.168.1.1/c/abc/manifest.json")
  end

  test "rejects link-local 169.254.x (AWS metadata)" do
    assert_not UrlGuard.allowed?("http://169.254.169.254/latest/meta-data/")
  end

  test "rejects non-http schemes" do
    assert_not UrlGuard.allowed?("file:///etc/passwd")
    assert_not UrlGuard.allowed?("ftp://example.com/x")
  end

  test "rejects malformed URLs" do
    assert_not UrlGuard.allowed?("not a url")
    assert_not UrlGuard.allowed?("")
    assert_not UrlGuard.allowed?(nil)
  end
end
