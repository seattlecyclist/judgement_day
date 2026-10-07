require "net/http"
require "uri"

module JudgementDay
  # AllenAI MultiPref (allenai/multipref, ODC-By): everyday prompts, two
  # responses, and four independent votes per item (two regular workers, two
  # experts), with a tie option. Items, sample, slices and analysis follow the
  # 2026-10-07 amendment in PREREGISTRATION.md.
  module MultiPref
    DATASET = "allenai/multipref".freeze
    PAGE = 100
    RETRIES = 9
    PAGE_PAUSE = 0.5
    EXCLUDED_SOURCES = %w[anthropic/harmless-base].freeze
    SAMPLE = 2000
    THRESHOLD = Locked::THRESHOLD
    PRESETS = {
      "mp-smoke" => { slice: :dev, limit: 50, orders: 2, repeats: 1, cap: 1.0 },
      "mp-test" => { slice: :all, limit: nil, orders: 2, repeats: 3, cap: 5.0 }
    }.freeze

    module_function

    def raw_path
      JudgementDay.path("data", "raw", "multipref.jsonl")
    end

    def items_path
      JudgementDay.path("data", "multipref", "items.jsonl")
    end

    def fetch(http: Net::HTTP, pause: ->(s) { sleep(s) })
      rows = []
      offset = 0
      loop do
        uri = URI(Dataset::ROWS_URL)
        uri.query = URI.encode_www_form(dataset: DATASET, config: "default", split: "train", offset: offset, length: PAGE)
        res = nil
        RETRIES.times do |attempt|
          res = http.get_response(uri)
          break unless res.code.to_s == "429" || res.code.to_s.start_with?("5")
          pause.call(2**attempt)
        end
        raise Error, "MultiPref fetch failed (#{res.code}) at offset #{offset}" unless res.is_a?(Net::HTTPSuccess)
        page = JSON.parse(res.body)
        batch = page.fetch("rows").map { |r| r.fetch("row") }
        rows.concat(batch)
        offset += batch.size
        break if batch.empty? || offset >= page.fetch("num_rows_total")
        pause.call(PAGE_PAUSE)
      end
      JudgementDay.write_jsonl(raw_path, rows)
      rows
    end

    def vote(pref)
      case pref.to_s
      when /\AA-is-/ then "a"
      when /\AB-is-/ then "b"
      when "Tie" then "tie"
      end
    end

    def tally(annotations)
      counts = { "a" => 0, "b" => 0, "tie" => 0 }
      Array(annotations).each { |a| (v = vote(a["overall_pref"])) && counts[v] += 1 }
      counts
    end

    def build_items(rows)
      rows.reject { |r| EXCLUDED_SOURCES.include?(r["source"]) }.map do |r|
        normal = tally(r["normal_worker_annotations"])
        expert = tally(r["expert_worker_annotations"])
        {
          "id" => "mp-#{r.fetch('comparison_id')}", "question_id" => r["prompt_id"], "turn" => 1,
          "category" => r["category"].to_s.empty? ? "other" : r["category"], "source" => r["source"],
          "model_a" => r["model_a"], "model_b" => r["model_b"],
          "conversation_a" => [{ "role" => "user", "content" => r["text"] }, { "role" => "assistant", "content" => r["completion_a"] }],
          "conversation_b" => [{ "role" => "user", "content" => r["text"] }, { "role" => "assistant", "content" => r["completion_b"] }],
          "votes" => normal.merge(expert) { |_, x, y| x + y }, "votes_normal" => normal, "votes_expert" => expert
        }
      end.uniq { |i| i["id"] }.sort_by { |i| i["id"] }
    end

    def load_items
      raise Error, "No MultiPref items yet: run `bin/jd fetch --dataset multipref` first" unless File.exist?(items_path)
      JudgementDay.read_jsonl(items_path)
    end

    def sample(items)
      Dataset.sample(items, SAMPLE)
    end

    def dev?(item_id)
      Metrics.holdout?(item_id)
    end

    def items_for(preset, items = load_items)
      cfg = PRESETS.fetch(preset)
      chosen = sample(items)
      chosen = chosen.select { |i| dev?(i["id"]) } if cfg[:slice] == :dev
      cfg[:limit] ? chosen.first(cfg[:limit]) : chosen
    end

    def wilson(successes, n, z = 1.96)
      return nil if n.zero?
      p = successes.fdiv(n)
      centre = (p + z * z / (2 * n)) / (1 + z * z / n)
      half = z * Math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / (1 + z * z / n)
      [(centre - half).round(3), (centre + half).round(3)]
    end

    def agreement_against(summaries, votes_key)
      decided = summaries.select { |s| s["confidence"] >= THRESHOLD }.filter_map do |s|
        maj = Metrics.majority(s["item"][votes_key])
        maj && s["pick"] == maj
      end
      decided.empty? ? nil : decided.count(true).fdiv(decided.size)
    end

    # The preregistered analysis: isotonic map fitted on the dev slice, every
    # bar measured on the test slice.
    def evaluate(items, rows)
      summaries = Metrics.per_item(items, rows)
      dev = summaries.select { |s| dev?(s["item"]["id"]) }
      test = summaries.reject { |s| dev?(s["item"]["id"]) }
      map = Calibration.fit_isotonic(dev)
      mapped = Calibration.apply(test, map)
      judged = test.select { |s| s["majority"] }
      at = Metrics.at_threshold(test, THRESHOLD)
      strong = test.select { |s| s["majority"] && s["item"]["votes"][s["majority"]] >= 3 }
      votes = test.map { |s| s["item"]["votes"] }
      result = {
        "preregistration" => "2026-10-07 MultiPref amendment", "bars_version" => Metrics::BARS_VERSION,
        "threshold" => THRESHOLD, "items_scored" => summaries.size, "dev_items" => dev.size,
        "test_items" => test.size, "test_items_with_majority" => judged.size,
        "all" => at,
        "agreement_95ci" => at["decided"].to_i.positive? ? wilson((at["agreement"] * at["decided"]).round, at["decided"]) : nil,
        "calibration" => Metrics.calibration(mapped), "raw_calibration" => Metrics.calibration(test),
        "calibration_map" => map,
        "order_consistency" => Metrics.rate(test, "order_consistent", true),
        "repeat_flip_rate" => Metrics.rate(test, "repeat_flipped", true),
        "ties" => judged.count { |s| s["majority"] == "tie" },
        "ties_caught" => judged.count { |s| s["majority"] == "tie" && s["pick"] == "tie" },
        "by_category" => Metrics.by_category(test, THRESHOLD),
        "by_source" => test.group_by { |s| s["item"]["source"] }.sort.to_h { |k, ss| [k, Metrics.at_threshold(ss, THRESHOLD).slice("items", "decided", "coverage", "agreement")] },
        "three_of_four" => Metrics.at_threshold(strong, THRESHOLD).slice("items", "decided", "coverage", "agreement"),
        "agreement_vs_experts" => agreement_against(test, "votes_expert"),
        "agreement_vs_workers" => agreement_against(test, "votes_normal"),
        "human_votes_for_second" => votes.sum { |v| v["b"] }.fdiv([votes.sum { |v| v["a"] + v["b"] }, 1].max).round(3)
      }
      result["go"] = Metrics.go_checks(result.merge("holdout" => at))
      [result, summaries]
    end
  end
end
