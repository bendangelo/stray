require "test_helper"

class RankingHelperTest < ActionView::TestCase
  test "ranking_explanation_for exposes source name, weight, and muted" do
    item = items(:video_one)
    follow = follows(:two) # weight 0.5
    exp = ranking_explanation_for(item, follow)
    assert_equal "Test Channel", exp.source_name
    assert_equal 0.5, exp.weight
    assert_not exp.muted
    assert_nil exp.source_position
    assert_not exp.mixed
  end

  test "ranking_explanation_for passes through source_position and mixed" do
    item = items(:video_one)
    follow = follows(:one)
    exp = ranking_explanation_for(item, follow, source_position: 3, mixed: true)
    assert_equal 3, exp.source_position
    assert exp.mixed
  end

  test "ranking_explanation_for reflects muted flag" do
    item = items(:video_one)
    follow = follows(:one)
    follow.update!(muted: true)
    exp = ranking_explanation_for(item, follow.reload)
    assert exp.muted
  end
end
