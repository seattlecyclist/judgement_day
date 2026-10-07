module JudgementDay
  # Compares the judge with the human majority. Pure functions over items and
  # score rows, so they are easy to test and rerun.
  module Metrics
    LABELS = %w[a b tie].freeze
    THRESHOLDS = (50..99).map { |t| t / 100.0 }.freeze
    GO_BARS = {
      "agreement" => 0.90, "coverage" => 0.50, "calibration_gap" => 0.10,
      "order_consistency" => 0.90, "repeat_flip_rate" => 0.05
    }.freeze
    # v2 (decided 2026-10-07, before the next batch): the calibration bar is the
    # item-weighted average gap across bins. v1 used the worst bin with 5+
    # items, which mostly measures noise at a few hundred items.
    BARS_VERSION = "bars@v2".freeze
    MIN_DECIDED = 10 # don't pick a threshold that decides fewer items than this
    DEFAULT_THRESHOLD = 0.80

    module_function

    def argmax(p)
      LABELS.max_by { |l| p.fetch(l) }
    end

    def mean_p(rows)
      LABELS.to_h { |l| [l, rows.sum { |r| r["p"][l] } / rows.size] }
    end

    # The label with strictly the most votes, or nil when the top is shared.
    def majority(votes)
      top = votes.values.max
      leaders = votes.select { |_, n| n == top }.keys
      leaders.size == 1 ? leaders.first : nil
    end

    def agreement_share(votes, label)
      votes.fetch(label, 0).to_f / votes.values.sum
    end

    def holdout?(item_id)
      JudgementDay.unit_hash("split:" + item_id) < 0.2
    end

    # One summary per item: averaged probabilities, the judge's pick, its
    # confidence (the winning probability), and order and repeat stability.
    def per_item(items, rows)
      by_item = rows.group_by { |r| r["item_id"] }
      items.filter_map do |item|
        rs = by_item[item["id"]]
        next if rs.nil? || rs.empty?
        p = mean_p(rs)
        by_order = rs.group_by { |r| r["order"] }
        order_picks = by_order.transform_values { |o| argmax(mean_p(o)) }
        flipped = by_order.values.any? { |o| o.map { |r| argmax(r["p"]) }.uniq.size > 1 }
        maj = majority(item["votes"])
        {
          "item" => item, "p" => p, "pick" => argmax(p), "confidence" => p.values.max,
          "provider_confidence" => rs.sum { |r| r["confidence"].to_f } / rs.size,
          "order_consistent" => order_picks.size < 2 ? nil : order_picks.values.uniq.size == 1,
          "repeat_flipped" => rs.size > by_order.size ? flipped : nil,
          "majority" => maj, "agrees" => maj && argmax(p) == maj,
          "holdout" => holdout?(item["id"])
        }
      end
    end

    def at_threshold(summaries, t)
      judged = summaries.select { |s| s["majority"] }
      decided = judged.select { |s| s["confidence"] >= t }
      {
        "threshold" => t, "items" => judged.size, "decided" => decided.size,
        "coverage" => judged.empty? ? nil : decided.size.to_f / judged.size,
        "agreement" => decided.empty? ? nil : decided.count { |s| s["agrees"] }.to_f / decided.size
      }
    end

    def sweep(summaries)
      THRESHOLDS.map { |t| at_threshold(summaries, t) }
    end

    # The lowest threshold that meets the agreement bar on the dev split, so
    # the fewest items go to review.
    def choose_threshold(dev_sweep, bar: GO_BARS["agreement"])
      hit = dev_sweep.find { |s| s["agreement"] && s["agreement"] >= bar && s["decided"] >= MIN_DECIDED }
      hit && hit["threshold"]
    end

    def calibration(summaries)
      judged = summaries.select { |s| s["majority"] }
      bins = judged.group_by { |s| [(s["confidence"] * 10).floor, 9].min }
      rows = bins.sort.map do |bin, ss|
        stated = ss.sum { |s| s["confidence"] } / ss.size
        observed = ss.count { |s| s["agrees"] }.to_f / ss.size
        { "bin" => format("%.1f-%.1f", bin / 10.0, (bin + 1) / 10.0), "items" => ss.size,
          "stated" => stated.round(3), "observed" => observed.round(3), "gap" => (stated - observed).abs.round(3) }
      end
      sized = rows.select { |r| r["items"] >= 5 }
      mean = judged.empty? ? nil : (rows.sum { |r| r["gap"] * r["items"] } / judged.size).round(3)
      { "bins" => rows, "max_gap" => sized.map { |r| r["gap"] }.max, "mean_gap" => mean }
    end

    def rate(summaries, key, want)
      xs = summaries.map { |s| s[key] }.compact
      xs.empty? ? nil : xs.count { |x| x == want }.to_f / xs.size
    end

    def by_category(summaries, t)
      summaries.group_by { |s| s["item"]["category"] }.sort.to_h do |cat, ss|
        r = at_threshold(ss, t)
        [cat, r.slice("items", "decided", "coverage", "agreement")]
      end
    end

    def go_checks(result)
      measured = {
        "agreement" => result.dig("holdout", "agreement") || result.dig("all", "agreement"),
        "coverage" => result.dig("holdout", "coverage") || result.dig("all", "coverage"),
        "calibration_gap" => result.dig("calibration", "mean_gap"),
        "order_consistency" => result["order_consistency"],
        "repeat_flip_rate" => result["repeat_flip_rate"]
      }
      measured.to_h do |k, v|
        bar = GO_BARS[k]
        lower_is_better = %w[calibration_gap repeat_flip_rate].include?(k)
        pass = v.nil? ? nil : (lower_is_better ? v <= bar : v >= bar)
        [k, { "value" => v, "bar" => bar, "pass" => pass }]
      end
    end

    def evaluate(items, rows)
      summaries = per_item(items, rows)
      dev = summaries.reject { |s| s["holdout"] }
      dev_sweep = sweep(dev)
      chosen = choose_threshold(dev_sweep)
      t = chosen || DEFAULT_THRESHOLD
      result = {
        "items_scored" => summaries.size,
        "items_with_majority" => summaries.count { |s| s["majority"] },
        "threshold" => t, "threshold_calibrated" => !chosen.nil?,
        "sweep" => sweep(summaries), "dev_sweep" => dev_sweep,
        "all" => at_threshold(summaries, t),
        "holdout" => at_threshold(summaries.select { |s| s["holdout"] }, t),
        "calibration" => calibration(summaries),
        "order_consistency" => rate(summaries, "order_consistent", true),
        "repeat_flip_rate" => rate(summaries, "repeat_flipped", true),
        "by_category" => by_category(summaries, t),
        "confident_disagreements" => summaries.count { |s| s["majority"] && s["confidence"] >= t && !s["agrees"] }
      }
      result["go"] = go_checks(result)
      result["bars_version"] = BARS_VERSION
      [result, summaries]
    end
  end
end
