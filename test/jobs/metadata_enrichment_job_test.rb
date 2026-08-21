require "test_helper"
require "ostruct"

class MetadataEnrichmentJobTest < ActiveJob::TestCase
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
      url: "https://bitchute.com/video/vid1"
    )
  end

  def status_success
    OpenStruct.new(success?: true)
  end

  test "populates duration for items missing one" do
    json = '{"id":"vid1","title":"Video 1","duration":185}'
    stub_runner_execute([ json, "", status_success ]) do
      MetadataEnrichmentJob.perform_now(@source.id, [ @item.id ])
    end

    assert_equal 185, @item.reload.duration
  end

  test "populates thumbnail_url for items missing one" do
    json = '{"id":"vid1","title":"Video 1","thumbnail":"https://example.com/thumb.jpg"}'
    stub_runner_execute([ json, "", status_success ]) do
      MetadataEnrichmentJob.perform_now(@source.id, [ @item.id ])
    end

    assert_equal "https://example.com/thumb.jpg", @item.reload.thumbnail_url
  end

  test "populates published_at for items missing one" do
    json = '{"id":"vid1","title":"Video 1","upload_date":"20240115"}'
    stub_runner_execute([ json, "", status_success ]) do
      MetadataEnrichmentJob.perform_now(@source.id, [ @item.id ])
    end

    assert_equal Time.strptime("20240115", "%Y%m%d").utc, @item.reload.published_at
  end

  test "populates all missing fields in a single fetch" do
    json = '{"id":"vid1","title":"Video 1","duration":185,"thumbnail":"https://example.com/thumb.jpg","upload_date":"20240115"}'
    stub_runner_execute([ json, "", status_success ]) do
      MetadataEnrichmentJob.perform_now(@source.id, [ @item.id ])
    end

    item = @item.reload
    assert_equal 185, item.duration
    assert_equal "https://example.com/thumb.jpg", item.thumbnail_url
    assert_equal Time.strptime("20240115", "%Y%m%d").utc, item.published_at
  end

  test "skips items that already have all metadata" do
    @item.update!(duration: 300, thumbnail_url: "https://example.com/existing.jpg", published_at: 1.day.ago)
    stub_runner_execute(->(*_args) { raise "should not call yt-dlp" }) do
      MetadataEnrichmentJob.perform_now(@source.id, [ @item.id ])
    end

    item = @item.reload
    assert_equal 300, item.duration
    assert_equal "https://example.com/existing.jpg", item.thumbnail_url
    assert_equal 1.day.ago.to_i, item.published_at.to_i
  end

  test "leaves fields nil when yt-dlp returns none" do
    stub_runner_execute([ '{"id":"vid1","title":"Video 1"}', "", status_success ]) do
      MetadataEnrichmentJob.perform_now(@source.id, [ @item.id ])
    end

    item = @item.reload
    assert_nil item.duration
    assert_nil item.thumbnail_url
    assert_nil item.published_at
  end

  test "does not run for non-video sources" do
    rss_source = Source.create!(user: @user, kind: :rss_feed,
      url: "https://example.com/feed.xml", external_id: "rss1")
    item = rss_source.items.create!(user: @user, external_id: "a", title: "A",
      url: "https://example.com/a")

    stub_runner_execute(->(*_args) { raise "should not call yt-dlp" }) do
      MetadataEnrichmentJob.perform_now(rss_source.id, [ item.id ])
    end

    item = item.reload
    assert_nil item.duration
    assert_nil item.thumbnail_url
    assert_nil item.published_at
  end

  test "runs for site-specific video channel kinds" do
    bitchute_source = Source.create!(user: @user, kind: :bitchute_channel,
      url: "https://www.bitchute.com/channel/foo", external_id: "bc1")
    item = bitchute_source.items.create!(user: @user, external_id: "vid1", title: "Video 1",
      url: "https://www.bitchute.com/video/vid1")

    json = '{"id":"vid1","title":"Video 1","duration":185}'
    stub_runner_execute([ json, "", status_success ]) do
      MetadataEnrichmentJob.perform_now(bitchute_source.id, [ item.id ])
    end

    assert_equal 185, item.reload.duration
  end

  test "does not clobber existing duration when re-fetched" do
    @item.update!(duration: 300)
    json = '{"id":"vid1","title":"Video 1","duration":185}'
    stub_runner_execute([ json, "", status_success ]) do
      MetadataEnrichmentJob.perform_now(@source.id, [ @item.id ])
    end

    assert_equal 300, @item.reload.duration
  end

  private

  def stub_runner_execute(return_value)
    runner = Stray::YtDlp::Runner.new
    runner.define_singleton_method(:execute) { |*_args| return_value.is_a?(Proc) ? return_value.call : return_value }
    PoliteCrawl.stub(:sleep, nil) do
      Stray::YtDlp::Runner.stub(:new, runner) { yield }
    end
  end
end
