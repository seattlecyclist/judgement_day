module JudgementDay
  # The setup fixed on 2026-10-07 from the full MT-Bench run, before any
  # confirmation item was scored. Do not change it after looking at the
  # confirmation results; make a new version instead.
  #
  # Route on the judge's raw confidence (decide at 0.90, as the full run
  # chose), and report a calibrated probability from an isotonic map fitted
  # on all 384 full-run items with a human majority. The map never changes a
  # pick, so order and repeat stability are the raw judge's.
  #
  # A temperature + tie-bias map was considered and rejected: even on the
  # full run it was fitted on, its picks failed order consistency (89%) and
  # repeat stability (6.6% flips).
  module Locked
    VERSION = "locked@2026-10-07".freeze
    THRESHOLD = 0.90
    BARS_VERSION = "bars@v2".freeze
    # [raw confidence at least, calibrated probability]
    ISOTONIC_STEPS = [
      [0.3767, 0.0], [0.4267, 0.2], [0.535, 0.25], [0.5433, 0.3333], [0.5633, 0.3571],
      [0.6067, 0.5], [0.7217, 0.5556], [0.7433, 0.7258], [0.9033, 0.7391], [0.9367, 0.75],
      [0.9383, 0.8235], [0.9617, 0.8571], [0.9717, 0.8644], [0.995, 0.9412], [0.9967, 1.0]
    ].freeze

    module_function

    def calibrated(confidence)
      Calibration.isotonic_value(ISOTONIC_STEPS, confidence)
    end

    # Every go bar on every item, with nothing fitted or chosen on this data.
    def evaluate(items, rows)
      raise Error, "Locked to #{BARS_VERSION}, metrics are #{Metrics::BARS_VERSION}" unless Metrics::BARS_VERSION == BARS_VERSION
      summaries = Metrics.per_item(items, rows)
      judged = summaries.select { |s| s["majority"] }
      reported = summaries.map { |s| s.merge("confidence" => calibrated(s["confidence"])) }
      result = {
        "locked_version" => VERSION, "threshold" => THRESHOLD,
        "items_scored" => summaries.size, "items_with_majority" => judged.size,
        "all" => Metrics.at_threshold(summaries, THRESHOLD),
        "calibration" => Metrics.calibration(reported),
        "raw_calibration" => Metrics.calibration(summaries),
        "order_consistency" => Metrics.rate(summaries, "order_consistent", true),
        "repeat_flip_rate" => Metrics.rate(summaries, "repeat_flipped", true),
        "ties" => judged.count { |s| s["majority"] == "tie" },
        "ties_caught" => judged.count { |s| s["majority"] == "tie" && s["pick"] == "tie" },
        "by_category" => Metrics.by_category(summaries, THRESHOLD)
      }
      # Every confirmation item is unseen, so agreement and coverage are
      # measured on all of them, not a holdout slice.
      result["go"] = Metrics.go_checks(result.merge("holdout" => result["all"]))
      result["bars_version"] = BARS_VERSION
      [result, summaries]
    end
  end
end
