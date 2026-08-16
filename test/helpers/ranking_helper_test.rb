require "test_helper"

class RankingHelperTest < ActionView::TestCase
  test "ranking_explanation_for returns offset_hours and effective_at" do
    item = items(:video_one)
    follow = follows(:two) # weight 0.5
    exp = ranking_explanation_for(item, follow)
    assert_equal 0.5, exp.weight
    assert_equal -12.0, exp.offset_hours
    assert_equal item.published_at + (-12.hours), exp.effective_at
    assert_not exp.muted
  end

  test "ranking_explanation_for with weight 1.0 gives zero offset" do
    item = items(:video_one)
    follow = follows(:one) # weight 1.0
    exp = ranking_explanation_for(item, follow)
    assert_equal 0.0, exp.offset_hours
  end

  test "ranking_explanation_for reflects muted flag" do
    item = items(:video_one)
    follow = follows(:one)
    follow.update!(muted: true)
    exp = ranking_explanation_for(item, follow.reload)
    assert exp.muted
  end

  test "offset_label returns no adjustment for zero" do
    assert_equal "no weight adjustment", offset_label(0.0)
  end

  test "offset_label returns +N for positive" do
    assert_equal "+12.0h", offset_label(12.0)
  end

  test "offset_label returns -N for negative" do
    assert_equal "−5.0h", offset_label(-5.0)
  end
end
