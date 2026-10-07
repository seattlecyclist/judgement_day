require "test_helper"

class MultiPrefTest < Minitest::Test
  M = JudgementDay::MultiPref

  def ann(*prefs)
    prefs.map { |p| { "overall_pref" => p } }
  end

  def row(id, normal, expert, source: "lmsys/chatbot_arena_conversations")
    { "comparison_id" => id, "prompt_id" => "p#{id}", "text" => "Q#{id}", "completion_a" => "A#{id}", "completion_b" => "B#{id}",
      "model_a" => "m1", "model_b" => "m2", "category" => "Open QA", "source" => source,
      "normal_worker_annotations" => ann(*normal), "expert_worker_annotations" => ann(*expert) }
  end

  def test_builds_items_from_all_four_votes
    item = M.build_items([row("x", %w[A-is-clearly-better A-is-slightly-better], %w[Tie B-is-slightly-better])]).first
    assert_equal "mp-x", item["id"]
    assert_equal({ "a" => 2, "b" => 1, "tie" => 1 }, item["votes"])
    assert_equal({ "a" => 0, "b" => 1, "tie" => 1 }, item["votes_expert"])
    assert_equal "a", JudgementDay::Metrics.majority(item["votes"])
    assert_equal %w[Qx Ax], item["conversation_a"].map { |m| m["content"] }
    assert_equal %w[Qx Bx], item["conversation_b"].map { |m| m["content"] }
  end

  def test_drops_red_team_prompts
    items = M.build_items([row("x", %w[Tie Tie], %w[Tie Tie]), row("y", %w[Tie Tie], %w[Tie Tie], source: "anthropic/harmless-base")])
    assert_equal ["mp-x"], items.map { |i| i["id"] }
  end

  def test_fetch_retries_when_rate_limited
    ok = Struct.new(:code, :body) { def is_a?(k) = k == Net::HTTPSuccess || super }
    page = ok.new("200", JSON.generate("rows" => [{ "row" => row("x", [], []) }], "num_rows_total" => 1))
    responses = [Struct.new(:code).new("429"), page]
    http = Object.new
    http.define_singleton_method(:get_response) { |_uri| responses.shift }
    Dir.mktmpdir do |dir|
      M.singleton_class.alias_method(:orig_raw_path, :raw_path)
      M.define_singleton_method(:raw_path) { File.join(dir, "raw.jsonl") }
      rows = M.fetch(http: http, pause: ->(_s) {})
      assert_equal ["x"], rows.map { |r| r["comparison_id"] }
    ensure
      M.singleton_class.alias_method(:raw_path, :orig_raw_path)
    end
  end

  def test_agreement_against_one_group_counts_misses
    item = M.build_items([row("x", %w[A-is-clearly-better A-is-clearly-better], %w[B-is-clearly-better B-is-clearly-better])]).first
    summary = { "item" => item, "confidence" => 0.95, "pick" => "a" }
    assert_equal 1.0, M.agreement_against([summary], "votes_normal")
    assert_equal 0.0, M.agreement_against([summary], "votes_expert")
  end

  def test_bars_use_the_test_slice_and_the_map_is_fitted_on_dev
    rows_in = (1..60).map { |n| row(n.to_s, %w[A-is-clearly-better A-is-clearly-better], %w[A-is-slightly-better Tie]) }
    items = M.build_items(rows_in)
    rows = items.flat_map do |i|
      (0..1).map do |o|
        { "item_id" => i["id"], "order" => o, "repeat" => 0, "first_shown" => "a",
          "p" => { "a" => 0.95, "b" => 0.03, "tie" => 0.02 }, "confidence" => 0.9 }
      end
    end
    result, = M.evaluate(items, rows)
    dev = items.count { |i| M.dev?(i["id"]) }
    assert_operator dev, :>, 0
    assert_equal items.size - dev, result["test_items"]
    assert_equal dev, result["dev_items"]
    assert_equal 1.0, result.dig("all", "agreement")
    assert result.dig("go", "agreement", "pass")
  end
end
