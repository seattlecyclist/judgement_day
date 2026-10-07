require "minitest/autorun"
require "tmpdir"
require "judgement_day"

module Fixtures
  module_function

  def conv(q, a)
    [{ "role" => "user", "content" => q }, { "role" => "assistant", "content" => a }]
  end

  # Raw dataset rows: two judges on one pair (seen in both orientations),
  # one judge on another pair.
  def rows
    [
      { "question_id" => 101, "turn" => 1, "model_a" => "vicuna-13b", "model_b" => "alpaca-13b", "winner" => "model_a",
        "judge" => "expert_1", "conversation_a" => conv("Q", "vicuna says"), "conversation_b" => conv("Q", "alpaca says") },
      { "question_id" => 101, "turn" => 1, "model_a" => "alpaca-13b", "model_b" => "vicuna-13b", "winner" => "model_b",
        "judge" => "expert_2", "conversation_a" => conv("Q", "alpaca says"), "conversation_b" => conv("Q", "vicuna says") },
      { "question_id" => 81, "turn" => 2, "model_a" => "gpt-4", "model_b" => "claude-v1", "winner" => "tie",
        "judge" => "expert_3", "conversation_a" => conv("W", "g"), "conversation_b" => conv("W", "c") }
    ]
  end

  # A fake judge that returns fixed probabilities for response1/2 and tie.
  class FakeJudge
    attr_reader :calls

    def initialize(probs = { "response1" => 0.9, "response2" => 0.08, "tie" => 0.02 })
      @probs = probs
      @calls = 0
    end

    def call(_body)
      @calls += 1
      { "model" => "fake", "usage" => { "input_tokens" => 1000, "output_tokens" => 10 },
        "answers" => { "which_better" => { "choice" => "response1", "confidence" => 0.8, "probabilities" => @probs } } }
    end
  end
end
