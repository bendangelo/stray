require "test_helper"
require "ostruct"

class DurationEnrichmentJobTest < ActiveJob::TestCase
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

  test "populates duration for items missing one" do
    json = '{"id":"vid1","title":"Video 1","duration":185}'
    stub_runner_execute([ json, "", status_success ]) do
      DurationEnrichmentJob.perform_now(@source.id, [ @item.id ])
    end

    assert_equal 185, @item.reload.duration
  end

  test "skips items that already have a duration" do
    @item.update!(duration: 300)
    json = '{"id":"vid1","duration":185}'
    stub_runner_execute([ json, "", status_success ]) do
      DurationEnrichmentJob.perform_now(@source.id, [ @item.id ])
    end

    assert_equal 300, @item.reload.duration
  end

  test "leaves duration nil when yt-dlp returns none" do
    stub_runner_execute([ '{"id":"vid1","title":"Video 1"}', "", status_success ]) do
      DurationEnrichmentJob.perform_now(@source.id, [ @item.id ])
    end

    assert_nil @item.reload.duration
  end

  test "does not run for non-video sources" do
    rss_source = Source.create!(user: @user, kind: :rss_feed,
      url: "https://example.com/feed.xml", external_id: "rss1")
    item = rss_source.items.create!(user: @user, external_id: "a", title: "A",
      url: "https://example.com/a", published_at: 1.day.ago)

    stub_runner_execute(->(*_args) { raise "should not call yt-dlp" }) do
      DurationEnrichmentJob.perform_now(rss_source.id, [ item.id ])
    end

    assert_nil item.reload.duration
  end

  private

  def stub_runner_execute(return_value)
    runner = Stray::YtDlp::Runner.new
    runner.define_singleton_method(:execute) { |*_args| return_value.is_a?(Proc) ? return_value.call : return_value }
    Stray::YtDlp::Runner.stub(:new, runner) { yield }
  end
end
