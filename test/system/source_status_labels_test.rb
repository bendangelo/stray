require "test_helper"
require "application_system_test_case"

class SourceStatusLabelsTest < ApplicationSystemTestCase
  test "renders Resolving, Retrying, and Failed labels for different statuses" do
    sign_in_as(users(:one))

    pending = Source.create!(user: users(:one), kind: :rss_feed,
      url: "https://example.com/p", external_id: "p", status: :pending, polling: true)
    recov = Source.create!(user: users(:one), kind: :rss_feed,
      url: "https://example.com/r", external_id: "r", status: :recovering,
      last_error: "timeout", next_crawl_at: 3.minutes.from_now)
    failed = Source.create!(user: users(:one), kind: :rss_feed,
      url: "https://example.com/f", external_id: "f", status: :failed, last_error: "blocked")
    Follow.create!(user: users(:one), source: pending)
    Follow.create!(user: users(:one), source: recov)
    Follow.create!(user: users(:one), source: failed)

    visit sources_path

    assert_text "Resolving…"
    assert_text "Retrying"
    assert_text "Failed"
    assert_text "timeout"
    assert_text "blocked"
  end
end
