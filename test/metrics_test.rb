require "test_helper"

class MetricsTest < Minitest::Test
  M = JudgementDay::Metrics

  def item(id, votes)
    { "id" => id, "category" => "writing", "votes" => votes }
  end

  def row(id, p, order: 0, repeat: 0)
    { "item_id" => id, "order" => order, "repeat" => repeat, "p" => p, "confidence" => 0.5 }
  end

  def test_majority
    assert_equal "a", M.majority({ "a" => 2, "b" => 1, "tie" => 0 })
    assert_nil M.majority({ "a" => 1, "b" => 1, "tie" => 0 })
  end

  def test_order_consistency_and_agreement
    items = [item("x", { "a" => 2, "b" => 0, "tie" => 0 })]
    rows = [row("x", { "a" => 0.9, "b" => 0.05, "tie" => 0.05 }, order: 0),
            row("x", { "a" => 0.2, "b" => 0.7, "tie" => 0.1 }, order: 1)]
    s = M.per_item(items, rows).first
    assert_equal false, s["order_consistent"]
    assert_equal "a", s["pick"]
    assert s["agrees"]
    assert_in_delta 0.55, s["confidence"]
  end

  def test_choose_threshold_lowest_meeting_bar
    sweep = [{ "threshold" => 0.5, "agreement" => 0.8, "decided" => 50 },
             { "threshold" => 0.6, "agreement" => 0.91, "decided" => 40 },
             { "threshold" => 0.7, "agreement" => 0.95, "decided" => 30 }]
    assert_equal 0.6, M.choose_threshold(sweep)
    assert_nil M.choose_threshold([{ "threshold" => 0.5, "agreement" => 0.95, "decided" => 3 }])
  end

  def test_evaluate_reports_go_checks
    items = (1..30).map { |n| item("i#{n}", { "a" => 2, "b" => 0, "tie" => 0 }) }
    rows = items.flat_map { |i| [0, 1].map { |o| row(i["id"], { "a" => 0.9, "b" => 0.05, "tie" => 0.05 }, order: o) } }
    result, = M.evaluate(items, rows)
    assert_equal 1.0, result.dig("all", "agreement")
    assert_equal true, result.dig("go", "order_consistency", "pass")
    assert_nil result["repeat_flip_rate"]
  end
end
