require "test_helper"

class SourceManifestTest < ActiveSupport::TestCase
  def setup
    @source = sources(:youtube)
    @source.items.destroy_all
    @item1 = @source.items.create!(
      user: users(:one), external_id: "sm-1", title: "Older", url: "https://x/1",
      content_text: "old", published_at: 2.days.ago, state: 0
    )
    @item2 = @source.items.create!(
      user: users(:one), external_id: "sm-2", title: "Newer", url: "https://x/2",
      content_text: "new", content_html: "<p>new</p>",
      thumbnail_url: "https://x/2.jpg", published_at: 1.day.ago, state: 0
    )
  end

  test "format is stray-source, not stray-collection" do
    manifest = SourceManifest.build(@source, cursor: nil)
    assert_equal "stray-source", manifest[:format]
    assert_equal 1, manifest[:version]
  end

  test "source block has name, url, kind, icon_url, slug, item_count" do
    manifest = SourceManifest.build(@source, cursor: nil)
    src = manifest[:source]
    assert_equal @source.display_name, src[:name]
    assert_equal @source.url, src[:url]
    assert_equal @source.kind, src[:kind]
    assert_equal @source.icon_url, src[:icon_url]
    assert_equal @source.slug, src[:slug]
    assert_equal 2, src[:item_count]
  end

  test "has no sources array (single source)" do
    manifest = SourceManifest.build(@source, cursor: nil)
    assert_not manifest.key?(:sources)
  end

  test "producer block is present" do
    manifest = SourceManifest.build(@source, cursor: nil)
    assert manifest[:producer][:instance_name].present?
    assert manifest[:producer][:stray_version].present?
  end

  test "items ordered by published_at desc with full payload" do
    manifest = SourceManifest.build(@source, cursor: nil)
    titles = manifest[:items].map { |i| i[:title] }
    assert_equal [ "Newer", "Older" ], titles
    item = manifest[:items].find { |i| i[:external_id] == "sm-2" }
    assert_equal "<p>new</p>", item[:content_html]
    assert_equal "https://x/2.jpg", item[:thumbnail_url]
  end

  test "includes hidden items" do
    @item2.update!(state: :hidden)
    manifest = SourceManifest.build(@source, cursor: nil)
    ids = manifest[:items].map { |i| i[:external_id] }
    assert_includes ids, "sm-2"
  end

  test "pagination next_url uses /s/<slug>/manifest.json path" do
    first = SourceManifest.build(@source, cursor: nil, page_size: 1)
    assert first[:pagination][:has_more]
    url = first[:pagination][:next_url]
    assert_includes url, "/s/#{@source.slug}/manifest.json"
    assert_includes url, "cursor="
  end

  test "pagination with base_url is absolute" do
    first = SourceManifest.build(@source, cursor: nil, page_size: 1, base_url: "https://stray.example.com")
    assert first[:pagination][:next_url].start_with?("https://stray.example.com/s/")
  end

  test "second page returns remaining items" do
    first = SourceManifest.build(@source, cursor: nil, page_size: 1)
    second = SourceManifest.build(@source, cursor: first[:pagination][:next_cursor], page_size: 1)
    assert_not second[:pagination][:has_more]
    assert_equal 1, second[:items].size
  end
end
