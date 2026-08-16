require "test_helper"

class RemoteCollectionTest < ActiveSupport::TestCase
  def setup
    @source = Source.create!(user: users(:one), kind: :stray_collection,
      url: "https://stray.example.com/c/abc/manifest.json", external_id: "abc")
  end

  test "valid with source, user, and manifest_url" do
    rc = RemoteCollection.new(source: @source, user: users(:one),
      manifest_url: "https://stray.example.com/c/abc/manifest.json")
    assert rc.valid?
  end

  test "unique source (1:1)" do
    RemoteCollection.create!(source: @source, user: users(:one), manifest_url: @source.url)
    dup = RemoteCollection.new(source: @source, user: users(:one), manifest_url: @source.url)
    assert dup.invalid?
    assert_includes dup.errors[:source_id], "has already been taken"
  end

  test "unique user + manifest_url" do
    RemoteCollection.create!(source: @source, user: users(:one), manifest_url: @source.url)
    other_source = Source.create!(user: users(:one), kind: :stray_collection,
      url: "https://stray.example.com/c/abc/manifest.json?x", external_id: "abc2")
    dup = RemoteCollection.new(source: other_source, user: users(:one), manifest_url: @source.url)
    assert dup.invalid?
    assert_includes dup.errors[:manifest_url], "has already been taken"
  end

  test "destroyed when source destroyed" do
    rc = RemoteCollection.create!(source: @source, user: users(:one), manifest_url: @source.url)
    @source.destroy
    assert_not RemoteCollection.exists?(rc.id)
  end
end
