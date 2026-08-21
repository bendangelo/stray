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
    @runner.stub(:execute, [ @json, "", status_success ]) do
      result = @runner.single_video("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
      assert_equal "dQw4w9WgXcQ", result["id"]
      assert_equal "Rick Astley - Never Gonna Give You Up (Official Music Video)", result["title"]
      assert_equal 213, result["duration"]
      assert_equal "UCuAXFkgsw1L7xaCfnd5JJOw", result["channel_id"]
    end
  end

  test "single_video raises ExtractionFailed on non-zero exit" do
    @runner.stub(:execute, [ "", "", status_failure ]) do
      assert_raises(Stray::YtDlp::ExtractionFailed) do
        @runner.single_video("https://example.com/video")
      end
    end
  end

  test "single_video failure message surfaces stderr detail" do
    @runner.stub(:execute, [ "", "ERROR: Video unavailable\n", status_failure ]) do
      error = assert_raises(Stray::YtDlp::ExtractionFailed) do
        @runner.single_video("https://example.com/video")
      end
      assert_equal "ERROR: Video unavailable", error.message
    end
  end

  test "single_video failure message falls back when stderr empty" do
    @runner.stub(:execute, [ "", "", status_failure ]) do
      error = assert_raises(Stray::YtDlp::ExtractionFailed) do
        @runner.single_video("https://example.com/video")
      end
      assert_equal "yt-dlp exited with non-zero status", error.message
    end
  end

  test "single_video raises ExtractionFailed on invalid JSON" do
    @runner.stub(:execute, [ "", "not json", status_success ]) do
      assert_raises(Stray::YtDlp::ExtractionFailed) do
        @runner.single_video("https://example.com/video")
      end
    end
  end

  test "single_video raises Timeout when yt-dlp exceeds timeout" do
    runner = Stray::YtDlp::Runner.new(timeout: 0.01)
    fake_stdin = StringIO.new
    fake_stdout = StringIO.new
    fake_stderr = StringIO.new
    fake_wait_thr = Object.new
    def fake_wait_thr.pid = 99999
    def fake_wait_thr.value = sleep(1) && OpenStruct.new(success?: true)

    Open3.stub(:popen3, ->(*_args, &block) { block.call(fake_stdin, fake_stdout, fake_stderr, fake_wait_thr) }) do
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

    @runner.stub(:execute, [ multi_json, "", status_success ]) do
      result = @runner.channel_listings("https://bitchute.com/channel/abc")
      assert_equal 2, result.size
      assert_equal "vid1", result[0]["id"]
      assert_equal "vid2", result[1]["id"]
    end
  end

  test "channel_listings passes --playlist-end when limit is set" do
    captured = nil
    @runner.stub(:execute, ->(*args) { captured = args; [ "", "", status_success ] }) do
      @runner.channel_listings("https://bitchute.com/channel/abc", limit: 50)
    end
    assert_equal [ "yt-dlp", "--flat-playlist", "--dump-json", "--playlist-end", "50", "https://bitchute.com/channel/abc", { timeout: 120 } ], captured
  end

  test "channel_listings omits --playlist-end when limit is nil" do
    captured = nil
    @runner.stub(:execute, ->(*args) { captured = args; [ "", "", status_success ] }) do
      @runner.channel_listings("https://bitchute.com/channel/abc")
    end
    assert_equal [ "yt-dlp", "--flat-playlist", "--dump-json", "https://bitchute.com/channel/abc", { timeout: 120 } ], captured
  end

  test "channel_listings returns empty array for no output" do
    @runner.stub(:execute, [ "", "", status_success ]) do
      result = @runner.channel_listings("https://example.com/channel/empty")
      assert_equal [], result
    end
  end

  test "channel_listings raises ExtractionFailed on non-zero exit" do
    @runner.stub(:execute, [ "", "", status_failure ]) do
      assert_raises(Stray::YtDlp::ExtractionFailed) do
        @runner.channel_listings("https://example.com/channel/bad")
      end
    end
  end

  test "channel_metadata parses first JSON line and ignores the rest" do
    first = '{"id":"vid1","channel_id":"UC123","channel":"Test"}'
    second = '{"id":"vid2","channel_id":"UC123","channel":"Test"}'
    multi_json = "#{first}\n#{second}\n"

    @runner.stub(:execute, [ multi_json, "", status_success ]) do
      result = @runner.channel_metadata("https://www.youtube.com/@Test")
      assert_equal "vid1", result["id"]
      assert_equal "UC123", result["channel_id"]
    end
  end

  test "channel_metadata returns nil for empty output" do
    @runner.stub(:execute, [ "", "", status_success ]) do
      assert_nil @runner.channel_metadata("https://www.youtube.com/@Empty")
    end
  end

  test "channel_metadata raises ExtractionFailed on non-zero exit" do
    @runner.stub(:execute, [ "", "", status_failure ]) do
      assert_raises(Stray::YtDlp::ExtractionFailed) do
        @runner.channel_metadata("https://www.youtube.com/@Bad")
      end
    end
  end

  test "channel_metadata raises ExtractionFailed on invalid JSON" do
    @runner.stub(:execute, [ "not json\n", "", status_success ]) do
      assert_raises(Stray::YtDlp::ExtractionFailed) do
        @runner.channel_metadata("https://www.youtube.com/@Bad")
      end
    end
  end
end
