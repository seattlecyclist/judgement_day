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

### 2026-10-07: dataset, votes, sample and analysis (before any judge call on the new data)

Approved by Mike in the project thread. Before this amendment, the dataset was inspected only to check its fields and vote structure: about 1,100 rows read through the Hugging Face rows API, with no judge calls. Nothing below was chosen by looking at judge output on this data.

- **Dataset.** AllenAI MultiPref, `allenai/multipref`, config `default`, split `train` (10,461 rows), license ODC-By. Fetched through the rows API into `data/raw/multipref.jsonl`.
- **Items.** One item per row, id `mp-<comparison_id>`. Prompt `text`, response A `completion_a`, response B `completion_b`, one user turn and one assistant reply each. Rows whose `source` is `anthropic/harmless-base` (red-team prompts) are dropped as not everyday work.
- **Votes.** All four `overall_pref` votes count: two from `normal_worker_annotations` and two from `expert_worker_annotations`. `A-is-clearly-better` and `A-is-slightly-better` count as A, `Tie` as tie, and the two `B-is-...` values as B.
- **Majority.** As on MT-Bench: the label with strictly the most votes. Items without one (2-2 splits) are left out of agreement. A 2-1-1 split has a majority.
- **Sample.** 2,000 items: the first 2,000 of the filtered items ordered by `JudgementDay.unit_hash("sample:" + id)`.
- **Slices.** The dev slice is the 20% of sampled items where `Metrics.holdout?(id)` is true. The test slice is the other 80%. Every bar is measured on the test slice only.
- **Judge.** Unchanged from `Locked`: judge `jev-1.13.0`, rubric `pairwise-helpful@v1` (the tie wordings tried in `experiments/tie_wording` are not adopted), two orders, three repeats, probabilities averaged. The judge decides an item when its raw confidence is 0.90 or higher.
- **Calibration map.** Isotonic (`Calibration.fit_isotonic`), fitted on the dev slice's items with a majority, then applied to the test slice. The average calibration gap is measured on the mapped test confidences.
- **Gating bars.** The five bars above on the test slice. GO only if all five pass.
- **Also reported, not gating.**
  - The worst-bin gap and the raw unmapped average gap.
  - Agreement's 95% Wilson interval.
  - Ties caught.
  - Results by category and by source.
  - Agreement on the subset where 3 or 4 of the 4 votes agree.
  - Agreement against the experts' votes alone and the regular workers' votes alone.
  - The share of human votes for the second-listed response.
- **Runs and caps.**
  - `mp-smoke`: 50 dev-slice items, two orders, one repeat, $1 cap.
  - `mp-test`: all 2,000 sampled items, two orders, three repeats, $5 cap.
  - The smoke run only checks the pipeline, and its responses are reused from the cache by `mp-test`.
