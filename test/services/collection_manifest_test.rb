require "test_helper"

class CollectionManifestTest < ActiveSupport::TestCase
  def setup
    @collection = collections(:econ)
    @source = sources(:youtube)
    @source.items.destroy_all
    @item1 = @source.items.create!(
      user: users(:one), external_id: "vid1", title: "Older", url: "https://x/1",
      content_text: "old", published_at: 2.days.ago, state: 0
    )
    @item2 = @source.items.create!(
      user: users(:one), external_id: "manifest-new-2", title: "Newer", url: "https://x/2",
      content_text: "new", content_html: "<p>new</p>",
      thumbnail_url: "https://x/2.jpg", published_at: 1.day.ago, state: 0
    )
  end

  test "builds manifest with format, version, collection, producer" do
    manifest = CollectionManifest.build(@collection, cursor: nil)
    assert_equal "stray-collection", manifest[:format]
    assert_equal 1, manifest[:version]
    assert_equal "Economics Blogs", manifest[:collection][:name]
    assert_equal "econblogssecrettoken1234", manifest[:collection][:slug]
    assert manifest[:collection][:item_count] >= 2
    assert manifest[:producer][:instance_name].present?
  end

  test "items ordered by published_at desc" do
    manifest = CollectionManifest.build(@collection, cursor: nil)
    titles = manifest[:items].map { |i| i[:title] }
    assert_equal [ "Newer", "Older" ], titles
  end

  test "item includes required fields" do
    manifest = CollectionManifest.build(@collection, cursor: nil)
    item = manifest[:items].find { |i| i[:external_id] == "manifest-new-2" }
    assert_equal "Newer", item[:title]
    assert_equal "https://x/2", item[:url]
    assert_equal "new", item[:content_text]
    assert_equal "<p>new</p>", item[:content_html]
    assert_equal "https://x/2.jpg", item[:thumbnail_url]
    assert item[:published_at].is_a?(String)
    assert_nil item[:duration]
    assert_equal [], item[:tags]
  end

  test "item includes tags from taggings" do
    tag = Tag.create!(user: users(:one), name: "econ")
    Tagging.create!(item: @item2, tag: tag, source: :user)
    manifest = CollectionManifest.build(@collection, cursor: nil)
    item = manifest[:items].find { |i| i[:external_id] == "manifest-new-2" }
    assert_equal [ "econ" ], item[:tags]
  end

  test "excludes summary and embedding and state" do
    @item2.update!(summary: "secret llm summary")
    manifest = CollectionManifest.build(@collection, cursor: nil)
    item = manifest[:items].find { |i| i[:external_id] == "manifest-new-2" }
    assert_not item.key?(:summary)
    assert_not item.key?(:embedding)
    assert_not item.key?(:state)
  end

  test "includes hidden items" do
    @item2.update!(state: :hidden)
    manifest = CollectionManifest.build(@collection, cursor: nil)
    ids = manifest[:items].map { |i| i[:external_id] }
    assert_includes ids, "manifest-new-2"
  end

  test "sources list includes kind, name, url, icon_url" do
    manifest = CollectionManifest.build(@collection, cursor: nil)
    src = manifest[:sources].find { |s| s[:url] == @source.url }
    assert_equal "youtube_channel", src[:kind]
    assert_equal "Test Channel", src[:name]
  end

  test "cursor returns next page when more items" do
    manifest = CollectionManifest.build(@collection, cursor: nil, page_size: 1)
    assert manifest[:pagination][:has_more]
    assert manifest[:pagination][:next_cursor].present?
  end

  test "cursor nil when no more items" do
    manifest = CollectionManifest.build(@collection, cursor: nil)
    assert_not manifest[:pagination][:has_more]
    assert_nil manifest[:pagination][:next_cursor]
  end

  test "second page returns remaining items" do
    first = CollectionManifest.build(@collection, cursor: nil, page_size: 1)
    second = CollectionManifest.build(@collection, cursor: first[:pagination][:next_cursor], page_size: 1)
    assert_not second[:pagination][:has_more]
    assert_equal 1, second[:items].size
  end

  test "next_url includes cursor" do
    first = CollectionManifest.build(@collection, cursor: nil, page_size: 1)
    assert_includes first[:pagination][:next_url], "cursor="
  end
end
