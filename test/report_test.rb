require "test_helper"

class ReportTest < Minitest::Test
  def test_enriched_record_is_vendor_neutral
    item = JudgementDay::Dataset.build_items(Fixtures.rows, min_votes: 2).first
    s = { "item" => item, "p" => { "a" => 0.1, "b" => 0.85, "tie" => 0.05 }, "pick" => "b", "confidence" => 0.85,
          "order_consistent" => true, "majority" => "b", "agrees" => true }
    rec = JudgementDay::Report.enriched(s, 0.8)
    assert_equal "qpj-judge-2026.10", rec.dig("ai_judge", "judge_version")
    assert_equal "done", rec["route"]
    refute_match(/jev|typesafe/i, JSON.generate(rec))
  end
end
