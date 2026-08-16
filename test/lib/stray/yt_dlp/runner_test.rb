require "test_helper"
require "ostruct"
require "minitest/mock"

class Stray::YtDlp::RunnerTest < ActiveSupport::TestCase
  FIXTURE_PATH = File.expand_path("../../../fixtures/files/yt_dlp_video.json", __dir__)

  def setup
    @json = File.read(FIXTURE_PATH)
    @runner = Stray::YtDlp::Runner.new
  end

  def status_success
    OpenStruct.new(success?: true)
  end

  def status_failure
    OpenStruct.new(success?: false)
  end

  test "single_video parses JSON output" do
    Open3.stub(:capture3, [ @json, "", status_success ]) do
      result = @runner.single_video("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
      assert_equal "dQw4w9WgXcQ", result["id"]
      assert_equal "Rick Astley - Never Gonna Give You Up (Official Music Video)", result["title"]
      assert_equal 213, result["duration"]
      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result["channel_id"]
    end
  end

  test "single_video raises ExtractionFailed on non-zero exit" do
    Open3.stub(:capture3, [ "", "", status_failure ]) do
      assert_raises(Stray::YtDlp::ExtractionFailed) do
        @runner.single_video("https://example.com/video")
      end
    end
  end

  test "single_video failure message surfaces stderr detail" do
    Open3.stub(:capture3, [ "", "ERROR: Video unavailable\n", status_failure ]) do
      error = assert_raises(Stray::YtDlp::ExtractionFailed) do
        @runner.single_video("https://example.com/video")
      end
      assert_equal "ERROR: Video unavailable", error.message
    end
  end

  test "single_video failure message falls back when stderr empty" do
    Open3.stub(:capture3, [ "", "", status_failure ]) do
      error = assert_raises(Stray::YtDlp::ExtractionFailed) do
        @runner.single_video("https://example.com/video")
      end
      assert_equal "yt-dlp exited with non-zero status", error.message
    end
  end

  test "single_video raises ExtractionFailed on invalid JSON" do
    Open3.stub(:capture3, [ "", "not json", status_success ]) do
      assert_raises(Stray::YtDlp::ExtractionFailed) do
        @runner.single_video("https://example.com/video")
      end
    end
  end

  test "single_video raises Timeout when yt-dlp exceeds timeout" do
    runner = Stray::YtDlp::Runner.new(timeout: 0.01)
    Open3.stub(:capture3, ->(*args) { sleep 1; [ "", "", status_success ] }) do
      assert_raises(Stray::YtDlp::Timeout) do
        runner.single_video("https://example.com/video")
      end
    end
  end

  test "constructor accepts binary and timeout options" do
    runner = Stray::YtDlp::Runner.new(binary: "/usr/local/bin/yt-dlp", timeout: 60)
    assert_equal "/usr/local/bin/yt-dlp", runner.binary
    assert_equal 60, runner.timeout
  end

  test "default binary is yt-dlp" do
    assert_equal "yt-dlp", @runner.binary
  end

  test "default timeout is 30" do
    assert_equal 30, @runner.timeout
  end

  test "channel_listings parses multiple JSON lines" do
    fixture1 = '{"id":"vid1","title":"Video 1","url":"https://example.com/v1"}'
    fixture2 = '{"id":"vid2","title":"Video 2","url":"https://example.com/v2"}'
    multi_json = "#{fixture1}\n#{fixture2}\n"

    Open3.stub(:capture3, [ multi_json, "", status_success ]) do
      result = @runner.channel_listings("https://bitchute.com/channel/abc")
      assert_equal 2, result.size
      assert_equal "vid1", result[0]["id"]
      assert_equal "vid2", result[1]["id"]
    end
  end

  test "channel_listings returns empty array for no output" do
    Open3.stub(:capture3, [ "", "", status_success ]) do
      result = @runner.channel_listings("https://example.com/channel/empty")
      assert_equal [], result
    end
  end

  test "channel_listings raises ExtractionFailed on non-zero exit" do
    Open3.stub(:capture3, [ "", "", status_failure ]) do
      assert_raises(Stray::YtDlp::ExtractionFailed) do
        @runner.channel_listings("https://example.com/channel/bad")
      end
    end
  end
end
