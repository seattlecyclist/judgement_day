module JudgementDay
  # Recalibrates the judge's averaged probabilities using human labels, with no
  # new judge calls. Fits on the dev split only and reports every go bar on the
  # holdout, before and after.
  #
  # Two maps are compared:
  # - scaling: a temperature that softens or sharpens all three probabilities,
  #   plus a bias on "tie" (the judge rarely calls one). Can change the pick.
  # - isotonic: a monotone curve from stated confidence to observed agreement.
  #   Keeps the pick and only restates how sure the judge is.
  # - both: scaling first, then isotonic on the scaled confidence.
  module Calibration
    TEMPERATURES = (5..60).map { |t| t / 10.0 }.freeze
    TIE_BIASES = (-20..40).map { |b| b / 10.0 }.freeze
    FOLDS = 5
    METHODS = %w[scaling isotonic both].freeze

    module_function

    # Temperature and tie bias applied to one probability triple.
    def scale(p, temperature:, tie_bias:)
      logits = Metrics::LABELS.to_h do |l|
        [l, Math.log([p.fetch(l), 1e-6].max) / temperature + (l == "tie" ? tie_bias : 0.0)]
      end
      top = logits.values.max
      exps = logits.transform_values { |v| Math.exp(v - top) }
      total = exps.values.sum
      exps.transform_values { |v| v / total }
    end

    def log_loss(summaries, temperature:, tie_bias:)
      summaries.sum do |s|
        -Math.log([scale(s["p"], temperature: temperature, tie_bias: tie_bias).fetch(s["majority"]), 1e-9].max)
      end / summaries.size
    end

    # Grid search for the temperature and tie bias with the lowest log loss
    # against the human majority.
    def fit_scaling(summaries)
      judged = summaries.select { |s| s["majority"] }
      best = TEMPERATURES.product(TIE_BIASES).min_by do |t, b|
        log_loss(judged, temperature: t, tie_bias: b)
      end
      { "method" => "scaling", "temperature" => best[0], "tie_bias" => best[1] }
    end

    # Pool-adjacent-violators: a non-decreasing step map from confidence to
    # the share of items where the judge agreed with the majority.
    def fit_isotonic(summaries)
      points = summaries.select { |s| s["majority"] }
                        .map { |s| [s["confidence"], s["agrees"] ? 1.0 : 0.0] }.sort_by(&:first)
      blocks = []
      points.each do |x, y|
        blocks << { lo: x, hi: x, sum: y, n: 1 }
        while blocks.size > 1 && blocks[-2][:sum] / blocks[-2][:n] >= blocks[-1][:sum] / blocks[-1][:n]
          last = blocks.pop
          blocks[-1] = { lo: blocks[-1][:lo], hi: last[:hi], sum: blocks[-1][:sum] + last[:sum], n: blocks[-1][:n] + last[:n] }
        end
      end
      { "method" => "isotonic", "steps" => blocks.map { |b| [b[:lo].round(4), (b[:sum] / b[:n]).round(4)] } }
    end

    def isotonic_value(steps, confidence)
      step = steps.reverse.find { |lo, _| confidence >= lo } || steps.first
      step[1]
    end

    # A copy of each summary with the map applied: new probabilities, pick,
    # confidence and agreement.
    def apply(summaries, map)
      summaries.map do |s|
        case map["method"]
        when "scaling"
          p = scale(s["p"], temperature: map["temperature"], tie_bias: map["tie_bias"])
          pick = Metrics.argmax(p)
          s.merge("p" => p, "pick" => pick, "confidence" => p.values.max,
                  "agrees" => s["majority"] && pick == s["majority"])
        when "isotonic"
          s.merge("confidence" => isotonic_value(map["steps"], s["confidence"]))
        when "both"
          apply(apply([s], map["scaling"]), map["isotonic"]).first
        else
          s
        end
      end
    end

    def fit(method, summaries)
      case method
      when "scaling" then fit_scaling(summaries)
      when "isotonic" then fit_isotonic(summaries)
      when "both"
        scaling = fit_scaling(summaries)
        { "method" => "both", "scaling" => scaling, "isotonic" => fit_isotonic(apply(summaries, scaling)) }
      end
    end

    # Out-of-fold calibration on the dev split: each fold is mapped by a fit
    # on the other folds, so the gap is measured on items the map never saw.
    def cross_validated(method, dev)
      folds = dev.group_by { |s| (JudgementDay.unit_hash("fold:" + s["item"]["id"]) * FOLDS).floor }
      folds.flat_map do |k, held|
        train = folds.reject { |j, _| j == k }.values.flatten
        apply(held, fit(method, train))
      end
    end

    # Every go bar for summaries already mapped, with the threshold chosen on
    # the dev split as in Metrics.evaluate. `unseen` is the same items mapped
    # only by fits that never saw them, which is what the calibration gap is
    # measured on.
    def bars(summaries, unseen)
      dev = summaries.reject { |s| s["holdout"] }
      chosen = Metrics.choose_threshold(Metrics.sweep(dev))
      t = chosen || Metrics::DEFAULT_THRESHOLD
      holdout = Metrics.at_threshold(summaries.select { |s| s["holdout"] }, t)
      judged = unseen.select { |s| s["majority"] }
      calibration = Metrics.calibration(unseen)
      {
        "threshold" => t, "threshold_calibrated" => !chosen.nil?,
        "agreement" => holdout["agreement"], "coverage" => holdout["coverage"],
        "holdout_decided" => holdout["decided"],
        "calibration_gap" => calibration["max_gap"], "mean_calibration_gap" => mean_gap(judged),
        "calibration" => calibration,
        "ties" => judged.count { |s| s["majority"] == "tie" },
        "ties_caught" => judged.count { |s| s["majority"] == "tie" && s["pick"] == "tie" },
        "ties_called" => judged.count { |s| s["pick"] == "tie" },
        "agreement_all_items" => judged.count { |s| s["agrees"] }.fdiv(judged.size)
      }
    end

    # Expected calibration error: the item-weighted average gap across bins.
    def mean_gap(summaries)
      return nil if summaries.empty?
      Metrics.calibration(summaries)["bins"].sum { |b| b["gap"] * b["items"] } / summaries.size
    end

    # Raw output against both maps. Each map is fitted on the dev split; its
    # calibration gap is measured out of sample (dev items by 5-fold
    # cross-validation, holdout items by the full dev fit).
    def evaluate(items, rows)
      summaries = Metrics.per_item(items, rows)
      dev = summaries.reject { |s| s["holdout"] }
      holdout = summaries.select { |s| s["holdout"] }
      result = { "raw" => bars(summaries, summaries) }
      METHODS.each do |method|
        map = fit(method, dev)
        unseen = cross_validated(method, dev) + apply(holdout, map)
        result[method] = bars(apply(summaries, map), unseen).merge("map" => map)
      end
      result
    end
  end
end
