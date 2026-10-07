module JudgementDay
  # Writes a run's results: the metrics report and the enriched sample file,
  # one record per item in the customer-facing format.
  module Report
    module_function

    def run_dir(run)
      JudgementDay.path("data", "runs", run)
    end

    def scores_path(run)
      File.join(run_dir(run), "scores.jsonl")
    end

    def enriched(summary, threshold)
      item = summary["item"]
      votes = item["votes"]
      maj = summary["majority"]
      confident = summary["confidence"] >= threshold
      order_check = case summary["order_consistent"]
                    when true then "consistent"
                    when false then "inconsistent"
                    else "not_checked"
                    end
      {
        "item_id" => item["id"], "question_id" => item["question_id"], "turn" => item["turn"],
        "category" => item["category"], "model_a" => item["model_a"], "model_b" => item["model_b"],
        "human" => { "votes" => votes, "majority" => maj,
                     "agreement" => maj && Metrics.agreement_share(votes, maj).round(2) },
        "ai_judge" => {
          "judge_version" => JUDGE_VERSION, "rubric" => Judge::RUBRIC_VERSION,
          "p" => summary["p"].transform_values { |v| v.round(3) },
          "order_check" => order_check,
          "confidence" => summary["confidence"].round(3),
          "band" => confident ? "confident" : "uncertain",
          "agrees_with_majority" => maj ? summary["agrees"] : nil
        },
        "route" => confident && summary["agrees"] ? "done" : "add_raters"
      }
    end

    def write(run, items)
      rows = JudgementDay.read_jsonl(scores_path(run))
      raise Error, "No scores for run #{run}" if rows.empty?
      result, summaries = Metrics.evaluate(items, rows)
      result["run"] = run
      result["generated_at"] = Time.now.utc.iso8601
      result["spend"] = Budget.totals.select { |(r, _), _| r == run }.transform_keys { |(_, k)| k }
      File.write(File.join(run_dir(run), "report.json"), JSON.pretty_generate(result))
      JudgementDay.write_jsonl(File.join(run_dir(run), "enriched.jsonl"),
                               summaries.map { |s| enriched(s, result["threshold"]) })
      [result, summaries]
    end

    def print_summary(result, io: $stdout)
      pct = ->(x) { x.nil? ? "n/a" : format("%.1f%%", x * 100) }
      io.puts "Run #{result['run']}: #{result['items_scored']} items, #{result['items_with_majority']} with a human majority"
      io.puts "Threshold #{result['threshold']} (#{result['threshold_calibrated'] ? 'calibrated' : 'default, not calibrated'})"
      result["go"].each do |k, v|
        mark = v["pass"].nil? ? "-" : (v["pass"] ? "PASS" : "MISS")
        val = k == "calibration_gap" ? (v["value"] ? format("%.3f", v["value"]) : "n/a") : pct.(v["value"])
        io.puts format("  %-18s %-8s bar %-6s %s", k, val, v["bar"], mark)
      end
      io.puts "  confident disagreements: #{result['confident_disagreements']}"
    end
  end
end
