require "test_helper"

class Youtube::OembedTest < ActiveSupport::TestCase
  test "fetch returns result for a watch URL" do
    body = {
      "title" => "Never Gonna Give You Up",
      "author_name" => "Rick Astley",
      "author_url" => "https://www.youtube.com/@RickAstley",
      "thumbnail_url" => "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
    }.to_json

    stub_oembed(body) do
      result = Youtube::Oembed.fetch("https://www.youtube.com/watch?v=dQw4w9WgXcQ")

      assert_equal "dQw4w9WgXcQ", result.external_id
      assert_equal "Never Gonna Give You Up", result.title
      assert_equal "Rick Astley", result.author_name
      assert_equal "https://www.youtube.com/@RickAstley", result.author_url
      assert_equal "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg", result.thumbnail_url
    end
  end

  test "fetch returns result for a youtu.be URL" do
    body = {
      "title" => "Never Gonna Give You Up",
      "author_name" => "Rick Astley",
      "author_url" => "https://www.youtube.com/@RickAstley",
      "thumbnail_url" => nil
    }.to_json

    stub_oembed(body) do
      result = Youtube::Oembed.fetch("https://youtu.be/dQw4w9WgXcQ")

      assert_equal "dQw4w9WgXcQ", result.external_id
    end
  end

  test "fetch raises on non-200 response" do
    response = Struct.new(:status, :body).new(404, "not found")
    client = Minitest::Mock.new
    client.expect(:get, response, [ String, Hash ])
    Youtube::Oembed.stub(:http_client, client) do
      assert_raises(Stray::ExtractionError) do
        Youtube::Oembed.fetch("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
      end
    end
  end

  test "fetch raises on malformed JSON" do
    response = Struct.new(:status, :body).new(200, "not json")
    client = Minitest::Mock.new
    client.expect(:get, response, [ String, Hash ])
    Youtube::Oembed.stub(:http_client, client) do
      assert_raises(Stray::ExtractionError) do
        Youtube::Oembed.fetch("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
      end
    end
  end

  test "fetch raises for non-YouTube URL" do
    assert_raises(ArgumentError) do
      Youtube::Oembed.fetch("https://example.com/video")
    end
  end

  private

  def stub_oembed(body)
    response = Struct.new(:status, :body).new(200, body)
    client = Minitest::Mock.new
    client.expect(:get, response, [ String, Hash ])
    Youtube::Oembed.stub(:http_client, client) do
      yield
    end
  end
end
