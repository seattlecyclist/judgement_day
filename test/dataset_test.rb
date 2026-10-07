require "test_helper"

class DatasetTest < Minitest::Test
  def test_groups_votes_across_orientations
    items = JudgementDay::Dataset.build_items(Fixtures.rows, min_votes: 1)
    pair = items.find { |i| i["question_id"] == 101 }
    assert_equal "alpaca-13b", pair["model_a"]
    assert_equal({ "a" => 0, "b" => 2, "tie" => 0 }, pair["votes"])
    assert_equal "alpaca says", pair["conversation_a"].last["content"]
    assert_equal "reasoning", pair["category"]
  end

  def test_min_votes_filter
    items = JudgementDay::Dataset.build_items(Fixtures.rows, min_votes: 2)
    assert_equal ["q101-t1-alpaca-13b-vs-vicuna-13b"], items.map { |i| i["id"] }
  end

  def test_categories
    assert_equal "writing", JudgementDay::Dataset.category(81)
    assert_equal "humanities", JudgementDay::Dataset.category(160)
  end
end
