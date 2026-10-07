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

  def test_turn_one_items_drop_the_second_turn
    two_turns = Fixtures.conv("Q1", "first answer") + Fixtures.conv("Q2", "second answer")
    rows = Fixtures.rows.first(2).map { |r| r.merge("conversation_a" => two_turns, "conversation_b" => two_turns) }
    item = JudgementDay::Dataset.build_items(rows, min_votes: 1).first
    assert_equal 1, item["turn"]
    assert_equal 2, item["conversation_a"].size
    assert_equal "first answer", item["conversation_a"].last["content"]

    turn2 = JudgementDay::Dataset.build_items(rows.map { |r| r.merge("turn" => 2) }, min_votes: 1).first
    assert_equal "second answer", turn2["conversation_b"].last["content"]
  end

  def test_min_votes_filter
    items = JudgementDay::Dataset.build_items(Fixtures.rows, min_votes: 2)
    assert_equal ["q101-t1-alpaca-13b-vs-vicuna-13b"], items.map { |i| i["id"] }
  end

  def test_categories
    assert_equal "writing", JudgementDay::Dataset.category(81)
    assert_equal "humanities", JudgementDay::Dataset.category(160)
  end

  def test_read_jsonl_is_utf8_regardless_of_locale
    Dir.mktmpdir do |dir|
      file = File.join(dir, "rows.jsonl")
      JudgementDay.write_jsonl(file, [{ "text" => "it’s café" }])
      previous = Encoding.default_external
      begin
        Encoding.default_external = Encoding::US_ASCII
        assert_equal "it’s café", JudgementDay.read_jsonl(file).first["text"]
      ensure
        Encoding.default_external = previous
      end
    end
  end
end
