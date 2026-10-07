# Pilot learnings (2026-10-07)

Two tests of the same locked judge setup. Results page and full write-up live
outside the repo; the numbers below come from `data/runs/confirm/locked_report.json`
and `data/runs/mp-test/prereg_report.json`.

| Bar | MT-Bench, 461 fresh items | MultiPref, 1,588 everyday items |
|---|---|---|
| Agreement (>= 90%) | 90.6% | 90.0% (95% CI 87-92%) |
| Coverage (>= 50%) | 62.4% | 36.6% miss |
| Average calibration gap (<= 0.10) | 0.063 | 0.050 |
| Order consistency (>= 90%) | 91.1% | 82.1% miss |
| Repeat flip rate (<= 5%) | 4.8% | 5.8% miss |
| Verdict | GO under bars@v2; 4 of 5 under the original worst-bin bar | NO-GO, 2 of 5 (preregistered) |
| Human ties caught | 10 of 76 | 45 of 294 |

## The judge

- Confident calls (raw confidence >= 0.90) agree with the human majority about
  90% of the time on both datasets, against experts and regular raters alike.
- How often it is confident depends on the data: 62% of MT-Bench items, 37% of
  everyday items, 26% of WildChat items. Savings must be measured per customer.
- Ties are a structural blind spot. Rewording the rubric moved ties caught
  from 13 to 16 of 53 (`experiments/tie_wording`, not adopted).
- Raw probabilities are overconfident (average gap about 0.12 on both
  datasets). An isotonic map fitted on about 400 labeled items fixes it.
- Always judge both orders: order swaps changed the pick on 9-18% of items.

## The human data

- Human labels are noisy. AI reviewers blamed the humans in about half of the
  confident MT-Bench disagreements. MultiPref raters gave 66% of their A-or-B
  votes to the second-shown answer.

## The method

- Check the data pipeline first: the turn-1 bug (fixed in 7a38ae6) alone moved
  MT-Bench agreement from 82% to 92%.
- Fix the bars before looking at data (`PREREGISTRATION.md`). Changing the
  calibration bar after a miss made the MT-Bench GO arguable.
- Worst-bin calibration swings on a handful of items; use the item-weighted
  average gap and report the worst bin alongside.
- Smoke runs first, hard caps on every run, cache every call. Whole pilot: $3.61.

## How QP would use it

Inside QP's operation: route confident items to fewer raters, and flag
confident judge-vs-rater disagreements for rater quality review. Sold: human
labels with a calibration report, plus an optional vendor-neutral `ai_judge`
field. Not sold: an AI score as a replacement for human labels.
