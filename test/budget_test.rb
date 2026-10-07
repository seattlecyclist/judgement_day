require "test_helper"

class BudgetTest < Minitest::Test
  def test_judge_cost
    assert_in_delta 0.042, JudgementDay::Budget.cost(:judge, input_tokens: 1_000_000)
  end

  def test_check_raises_when_estimate_crosses_cap
    Dir.mktmpdir do |d|
      b = JudgementDay::Budget.new(cap: 0.01, run: "t", ledger: File.join(d, "s.jsonl"))
      assert_raises(JudgementDay::BudgetExceeded) { b.check!(:reviewer, input_chars: 3000, max_output_tokens: 4000) }
      b.check!(:judge, input_chars: 3000)
    end
  end
end
