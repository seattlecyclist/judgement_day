require "test_helper"

class ScorerTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @items = JudgementDay::Dataset.build_items(Fixtures.rows, min_votes: 1)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def scorer(client, cap: 1.0)
    budget = JudgementDay::Budget.new(cap: cap, run: "t", ledger: File.join(@dir, "spend.jsonl"))
    JudgementDay::Scorer.new(client: client, budget: budget, cache_dir: File.join(@dir, "cache"), log: StringIO.new)
  end

  def test_second_run_uses_cache
    client = Fixtures::FakeJudge.new
    rows = scorer(client).score(@items, orders: 2, repeats: 2)
    assert_equal 8, rows.size
    assert_equal 8, client.calls
    scorer(client).score(@items, orders: 2, repeats: 2)
    assert_equal 8, client.calls
  end

  def test_cap_stops_before_overspending
    client = Fixtures::FakeJudge.new
    rows = scorer(client, cap: 0.0).score(@items, orders: 1, repeats: 1)
    assert_equal 0, client.calls
    assert_empty rows
  end
end
