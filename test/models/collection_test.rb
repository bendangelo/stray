require "test_helper"

class CollectionTest < ActiveSupport::TestCase
  test "valid with name and user" do
    collection = Collection.new(user: users(:one), name: "My Blogs")
    assert collection.valid?
  end

  test "invalid without name" do
    collection = Collection.new(user: users(:one))
    assert collection.invalid?
    assert_includes collection.errors[:name], "can't be blank"
  end

  test "invalid without user" do
    collection = Collection.new(name: "No user")
    assert collection.invalid?
    assert_includes collection.errors[:user], "must exist"
  end

  test "generates slug on create" do
    collection = Collection.create!(user: users(:one), name: "My Blogs")
    assert collection.slug.present?
    assert collection.slug.length >= 24
  end

  test "slug is unique per user" do
    first = Collection.create!(user: users(:one), name: "First")
    second = Collection.new(user: users(:one), slug: first.slug, name: "Second")
    assert second.invalid?
    assert_includes second.errors[:slug], "has already been taken"
  end

  test "default visibility is unlisted" do
    collection = Collection.new(user: users(:one), name: "X")
    assert collection.unlisted?
    assert_not collection.private?
  end

  test "can set visibility to private" do
    collection = Collection.new(user: users(:one), name: "X", visibility: :private)
    assert collection.private?
  end
end
