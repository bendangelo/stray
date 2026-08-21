require "test_helper"

class ArticleBodyScrubberTest < ActiveSupport::TestCase
  setup do
    @scrubber = ArticleBodyScrubber.new
  end

  test "permits basic paragraphs and formatting" do
    html = %(<p>Hello <strong>world</strong></p>)
    assert_equal %(<p>Hello <strong>world</strong></p>), sanitize_html(html)
  end

  test "permits links with http hrefs" do
    html = %(<a href="https://example.com">link</a>)
    assert_equal %(<a href="https://example.com">link</a>), sanitize_html(html)
  end

  test "permits images with http srcs" do
    html = %(<img src="https://example.com/a.png" alt="a">)
    result = sanitize_html(html)
    assert_includes result, %(src="https://example.com/a.png")
    assert_includes result, %(alt="a")
  end

  test "permits data: image srcs" do
    html = %(<img src="data:image/png;base64,iVBORw0KGgo=" alt="a">)
    result = sanitize_html(html)
    assert_includes result, "data:image/png;base64,"
  end

  test "strips script tags" do
    html = %(<p>ok</p><script>alert(1)</script>)
    assert_equal "<p>ok</p>", sanitize_html(html)
  end

  test "strips iframe tags" do
    html = %(<p>ok</p><iframe src="https://evil.com"></iframe>)
    assert_equal "<p>ok</p>", sanitize_html(html)
  end

  test "strips style tags" do
    html = %(<p>ok</p><style>body{color:red}</style>)
    assert_equal "<p>ok</p>", sanitize_html(html)
  end

  test "strips event handler attributes" do
    html = %(<p onclick="alert(1)">ok</p>)
    assert_equal "<p>ok</p>", sanitize_html(html)
  end

  test "drops links with javascript: hrefs" do
    html = %(<a href="javascript:alert(1)">link</a>)
    result = sanitize_html(html)
    assert_not_includes result, "javascript:"
  end

  test "drops links with data: text/html hrefs" do
    html = %(<a href="data:text/html,<script>alert(1)</script>">link</a>)
    result = sanitize_html(html)
    assert_not_includes result, "data:text/html"
  end

  test "permits headers, lists, blockquotes, tables, code" do
    html = %(<h1>Title</h1><ul><li>one</li></ul><blockquote>q</blockquote><table><tr><td>c</td></tr></table><pre><code>code</code></pre>)
    result = sanitize_html(html)
    assert_includes result, "<h1>Title</h1>"
    assert_includes result, "<ul><li>one</li></ul>"
    assert_includes result, "<blockquote>q</blockquote>"
    assert_includes result, "<pre><code>code</code></pre>"
  end

  private

  def sanitize_html(html)
    Rails::HTML::SafeListSanitizer.new.sanitize(html, scrubber: @scrubber).to_s
  end
end
