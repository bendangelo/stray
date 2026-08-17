require "test_helper"
require "ostruct"

class ThumbnailEnrichmentJobTest < ActiveJob::TestCase
  def setup
    @user = users(:one)
    @source = Source.create!(
      user: @user,
      kind: :video_channel,
      url: "https://bitchute.com/channel/abc",
      external_id: "abc"
    )
    @item = @source.items.create!(
      user: @user,
      external_id: "vid1",
      title: "Video 1",
      url: "https://bitchute.com/video/vid1",
      published_at: 1.day.ago
    )
  end

  def status_success
    OpenStruct.new(success?: true)
  end

  test "populates thumbnail_url for items missing one" do
    json = '{"id":"vid1","title":"Video 1","thumbnail":"https://example.com/thumb.jpg"}'
    stub_runner_execute([ json, "", status_success ]) do
      ThumbnailEnrichmentJob.perform_now(@source.id, [ @item.id ])
    end

    assert_equal "https://example.com/thumb.jpg", @item.reload.thumbnail_url
  end

  test "skips items that already have a thumbnail" do
    @item.update!(thumbnail_url: "https://example.com/existing.jpg")
    stub_runner_execute([ '{"id":"vid1","thumbnail":"https://example.com/new.jpg"}', "", status_success ]) do
      ThumbnailEnrichmentJob.perform_now(@source.id, [ @item.id ])
    end

    assert_equal "https://example.com/existing.jpg", @item.reload.thumbnail_url
  end

  test "leaves thumbnail nil when yt-dlp returns none" do
    stub_runner_execute([ '{"id":"vid1","title":"Video 1"}', "", status_success ]) do
      ThumbnailEnrichmentJob.perform_now(@source.id, [ @item.id ])
    end

    assert_nil @item.reload.thumbnail_url
  end

  private

  def stub_runner_execute(return_value)
    runner = Stray::YtDlp::Runner.new
    runner.define_singleton_method(:execute) { |*_args| return_value.is_a?(Proc) ? return_value.call : return_value }
    Stray::YtDlp::Runner.stub(:new, runner) { yield }
  end
end
