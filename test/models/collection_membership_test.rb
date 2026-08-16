require "test_helper"

class CollectionMembershipTest < ActiveSupport::TestCase
  test "valid with collection and source" do
    membership = CollectionMembership.new(collection: collections(:econ), source: sources(:bitchute))
    assert membership.valid?
  end

  test "unique per collection and source" do
    CollectionMembership.create!(collection: collections(:econ), source: sources(:bitchute))
    dup = CollectionMembership.new(collection: collections(:econ), source: sources(:bitchute))
    assert dup.invalid?
    assert_includes dup.errors[:source_id], "has already been taken"
  end

  test "destroyed when collection destroyed" do
    membership = CollectionMembership.create!(collection: collections(:econ), source: sources(:bitchute))
    collections(:econ).destroy
    assert_not CollectionMembership.exists?(membership.id)
  end
end
