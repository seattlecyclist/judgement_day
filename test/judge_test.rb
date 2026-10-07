require "test_helper"

class JudgeTest < Minitest::Test
  def item
    JudgementDay::Dataset.build_items(Fixtures.rows, min_votes: 2).first
  end

  def test_orders_swap_and_map_back
    first0 = JudgementDay::Judge.first_shown(item, 0)
    first1 = JudgementDay::Judge.first_shown(item, 1)
    refute_equal first0, first1
    probs = { "response1" => 0.7, "response2" => 0.2, "tie" => 0.1 }
    p0 = JudgementDay::Judge.to_ab(item, 0, probs)
    p1 = JudgementDay::Judge.to_ab(item, 1, probs)
    assert_equal 0.7, p0[first0]
    assert_equal 0.7, p1[first1]
  end

  def test_state_shows_first_response_first
    first = JudgementDay::Judge.first_shown(item, 0)
    text = item["conversation_#{first}"].last["content"]
    state = JudgementDay::Judge.state(item, 0)
    assert state.index(text) < state.index("## Response 2")
  end

  def test_request_pins_model
    assert_equal "jev-1.13.0", JudgementDay::Judge.request_body(item, 0)["model"]
  end
end
