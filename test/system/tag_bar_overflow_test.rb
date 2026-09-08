require "application_system_test_case"

class TagBarOverflowTest < ApplicationSystemTestCase
  test "tag bar shows first 10 tags inline then a More dropdown" do
    user = users(:one)
    # Create 15 tags with taggings on items the user follows
    15.times do |i|
      tag = Tag.create!(name: "tag-#{i}", user: user)
      Item.first.tap do |item|
        item.taggings.create!(tag: tag, source: :user) unless item.taggings.exists?(tag: tag)
      end
    end
    sign_in_as user
    visit root_path

    # "All" + 10 tags should be visible inline (11 links total)
    inline_links = all("#tag-bar > div > a", visible: true)
    assert_equal 11, inline_links.count, "should show 'All' + 10 tags inline"

    # "More" button should exist
    assert_selector "#tag-bar button[aria-label='More tags']"
  end

  test "clicking More reveals remaining tags in dropdown" do
    user = users(:one)
    15.times do |i|
      tag = Tag.create!(name: "tag-#{i}", user: user)
      Item.first.tap do |item|
        item.taggings.create!(tag: tag, source: :user) unless item.taggings.exists?(tag: tag)
      end
    end
    sign_in_as user
    visit root_path

    click_button "More"

    within "#tag-bar-more-dropdown" do
      remaining = all("a", visible: true)
      assert_equal 8, remaining.count, "dropdown should contain the remaining tags (18 total - 10 inline)"
    end
  end

  test "tag bar does not show More when fewer than 10 tags" do
    sign_in_as users(:one)
    visit root_path

    # Default fixtures have fewer than 10 tags
    refute_selector "#tag-bar button[aria-label='More tags']",
           wait: 0
  end
end
