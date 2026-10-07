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

  class SlowJudge < Fixtures::FakeJudge
    def call(body)
      sleep 0.02
      super
    end
  end

  def test_parallel_workers_keep_row_order_and_respect_cap
    client = SlowJudge.new
    rows = scorer(client).score(@items, orders: 2, repeats: 3)
    assert_equal @items.size * 6, rows.size
    expected = @items.flat_map { |i| (0..1).flat_map { |o| (0..2).map { |r| [i["id"], o, r] } } }
    assert_equal expected, rows.map { |r| [r["item_id"], r["order"], r["repeat"]] }

    # The cap stops new calls partway; finished calls are kept.
    capped = SlowJudge.new
    other = JudgementDay::Dataset.build_items(Fixtures.rows.map { |r| r.merge("question_id" => r["question_id"] + 1) }, min_votes: 1)
    rows = scorer(capped, cap: 0.0002).score(other, orders: 2, repeats: 3)
    assert_operator capped.calls, :<, other.size * 6
    assert_operator capped.calls, :>, 0
    assert_equal capped.calls, rows.size
  end
end
