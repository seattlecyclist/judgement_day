require "test_helper"

class LockedTest < Minitest::Test
  L = JudgementDay::Locked

  def item(id, votes)
    { "id" => id, "category" => "writing", "votes" => votes }
  end

  def row(id, p, order:, repeat: 0)
    { "item_id" => id, "order" => order, "repeat" => repeat, "p" => p, "confidence" => 0.5 }
  end

  def test_sample_offset_gives_disjoint_items
    items = 30.times.map { |i| item("i#{i}", { "a" => 2, "b" => 0, "tie" => 0 }) }
    first = JudgementDay::Dataset.sample(items, 10).map { |i| i["id"] }
    rest = JudgementDay::Dataset.sample(items, nil, offset: 10).map { |i| i["id"] }
    assert_empty first & rest
    assert_equal 30, (first + rest).uniq.size
  end

  def test_locked_setup_routes_on_raw_confidence_and_reports_calibrated
    items = [item("x", { "a" => 3, "b" => 0, "tie" => 0 }), item("y", { "a" => 0, "b" => 2, "tie" => 0 })]
    sure = { "a" => 0.95, "b" => 0.04, "tie" => 0.01 }
    unsure = { "a" => 0.2, "b" => 0.6, "tie" => 0.2 }
    rows = [row("x", sure, order: 0), row("x", sure, order: 1), row("y", unsure, order: 0), row("y", unsure, order: 1)]
    result, summaries = L.evaluate(items, rows)
    assert_equal 1, result.dig("all", "decided")
    assert_equal 1.0, result.dig("all", "agreement")
    assert_in_delta 0.95, summaries.first["confidence"]
    assert_in_delta 0.8235, L.calibrated(0.95)
    assert_equal 1.0, result["order_consistency"]
    assert_equal "bars@v2", result["bars_version"]
    assert_equal %w[agreement calibration_gap coverage order_consistency repeat_flip_rate], result["go"].keys.sort
  end
end
