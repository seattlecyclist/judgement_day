# Preregistration: second AI judge test

Committed 2026-10-07, before any item of the next dataset is downloaded or
scored. Nothing here changes after scoring starts. A change made before
scoring is a dated amendment at the bottom of this file, committed before the
first judge call on the new data.

## Why

The MT-Bench pilot passed only after the calibration bar was changed from the
worst bin to the average gap, prompted by a miss on the full run. This test
fixes every rule in advance so its result cannot be argued with the same way.

## Judge setup

- Judge, rubric and averaging as in `Locked` (locked@2026-10-07): two orders,
  three repeats, probabilities averaged.
- The judge decides an item when its raw confidence is 0.90 or higher.
  The threshold is not re-tuned on the new data.
- The reported probability goes through an isotonic map. The map is refitted
  on a dev slice of the new data (20% of items, chosen by
  `JudgementDay.unit_hash`), because MT-Bench confidence may not carry over.
  Every bar is measured on the other 80% only.
- A tie-wording change to the rubric may be adopted only if it is tested on
  MT-Bench or the new dev slice and committed here as an amendment before the
  test slice is scored.

## Go bars (bars@v2, as in `Metrics::GO_BARS`)

| Bar | Go if |
|---|---|
| Agreement with the human majority, on decided items | ≥ 0.90 |
| Coverage, share of items the judge decides | ≥ 0.50 |
| Average calibration gap (item-weighted, 10 bins) | ≤ 0.10 |
| Order consistency | ≥ 0.90 |
| Repeat flip rate | ≤ 0.05 |

GO means all five pass on the test slice. Anything else is NO-GO.

## Reported either way, not gating

- The worst-bin calibration gap (bins with 5+ items), the original bar.
- Agreement's 95% interval, ties caught, and results by category.
- Raw uncalibrated average gap next to the mapped one.

## Data requirements

Everyday prompts, two responses per item, and two or more independent human
votes per item so a majority exists. Items without a strict majority are left
out of agreement, as on MT-Bench. The dataset, its license and the sample
size are named in an amendment before scoring.

## Spend

Hard cap on every run, smoke run first. Paid runs need Mike's typed go.

## Amendments

(none yet)
