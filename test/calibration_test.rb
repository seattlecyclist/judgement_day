require "test_helper"

class CalibrationTest < Minitest::Test
  C = JudgementDay::Calibration

  def summary(id, p, majority, holdout: false)
    pick = JudgementDay::Metrics.argmax(p)
    { "item" => { "id" => id }, "p" => p, "pick" => pick, "confidence" => p.values.max,
      "majority" => majority, "agrees" => pick == majority, "holdout" => holdout }
  end

  def test_scale_identity_and_tie_bias
    p = { "a" => 0.7, "b" => 0.2, "tie" => 0.1 }
    C.scale(p, temperature: 1.0, tie_bias: 0.0).each { |k, v| assert_in_delta p[k], v, 1e-6 }
    softer = C.scale(p, temperature: 2.0, tie_bias: 0.0)
    assert_operator softer["a"], :<, 0.7
    assert_operator C.scale(p, temperature: 1.0, tie_bias: 2.0)["tie"], :>, 0.1
  end

  def test_isotonic_is_monotone_and_maps_overconfidence_down
    ss = 20.times.map { |i| summary("x#{i}", { "a" => 0.95, "b" => 0.04, "tie" => 0.01 }, i < 14 ? "a" : "b") } +
         20.times.map { |i| summary("y#{i}", { "a" => 0.55, "b" => 0.4, "tie" => 0.05 }, i < 6 ? "a" : "b") }
    map = C.fit_isotonic(ss)
    values = map["steps"].map(&:last)
    assert_equal values.sort, values
    assert_in_delta 0.7, C.isotonic_value(map["steps"], 0.95), 1e-6
    assert_in_delta 0.3, C.isotonic_value(map["steps"], 0.55), 1e-6
  end

  def test_scaling_learns_to_call_ties_the_judge_misses
    ss = 30.times.map { |i| summary("t#{i}", { "a" => 0.5, "b" => 0.2, "tie" => 0.3 }, "tie") } +
         10.times.map { |i| summary("a#{i}", { "a" => 0.8, "b" => 0.1, "tie" => 0.1 }, "a") }
    map = C.fit_scaling(ss)
    picks = C.apply(ss, map).map { |s| s["pick"] }
    assert_equal 30, picks.count("tie")
    assert_equal 10, picks.count("a")
  end
end
