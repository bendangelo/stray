require "test_helper"

class Stray::Extractors::GenericPageTest < ActiveSupport::TestCase
  test "matches? returns true for any http/https URL" do
    assert Stray::Extractors::GenericPage.matches?("https://example.com/blog/post-1")
    assert Stray::Extractors::GenericPage.matches?("http://example.com/about")
  end

  test "matches? returns false for non-http URLs" do
    assert_not Stray::Extractors::GenericPage.matches?("ftp://example.com/file")
    assert_not Stray::Extractors::GenericPage.matches?("not a url")
  end

  test "handles_kind? returns true for generic_page" do
    assert Stray::Extractors::GenericPage.handles_kind?("generic_page")
  end

  test "handles_kind? returns false for other kinds" do
    assert_not Stray::Extractors::GenericPage.handles_kind?("rss_feed")
    assert_not Stray::Extractors::GenericPage.handles_kind?("video_channel")
  end

  test "extract returns ExtractedContent from article page" do
    VCR.use_cassette("extractors/generic_page/article") do
      extractor = Stray::Extractors::GenericPage.new
      result = extractor.extract("https://example.com/articles/sample")

      assert_equal "https://example.com/articles/sample", result.url
      assert_equal "Example Article Title", result.title
      assert result.content_text.present?
      assert_includes result.content_text, "This is the main article body"
      assert result.content_html.present?
      assert_equal "https://example.com/image.jpg", result.thumbnail_url
      assert_equal "example.com", result.creator_identity.external_id
      assert_equal Digest::SHA256.hexdigest("https://example.com/articles/sample")[0, 32], result.external_id
      assert_nil result.duration
    end
  end

  test "extract_feed returns single-element array" do
    VCR.use_cassette("extractors/generic_page/article") do
      extractor = Stray::Extractors::GenericPage.new
      results = extractor.extract_feed("https://example.com/articles/sample")

      assert_equal 1, results.size
      assert_equal "Example Article Title", results.first.title
    end
  end

  test "extract raises when URL blocked by UrlGuard" do
    extractor = Stray::Extractors::GenericPage.new

    assert_raises(Stray::UrlGuard::Blocked) do
      extractor.extract("http://localhost:3000/admin")
    end
  end
end
