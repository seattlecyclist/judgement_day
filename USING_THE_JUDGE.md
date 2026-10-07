# How QP Judgement would use the AI judge

Written 2026-10-07 at the end of the desk pilot. It rests on three measured
runs, all in `data/runs/`:

- the MT-Bench full run;
- the locked confirmation run on 461 unused MT-Bench items;
- the preregistered MultiPref test on 1,588 everyday-prompt items.

## The short version

Use the judge as internal infrastructure that decides how much human work
each item needs. Don't sell it as a replacement for the panel.

On everyday prompts it is confident on about a third of items. When it is
confident it agrees with the human majority about 90% of the time. It is
weakest on the close calls and ties that customers pay human raters for.

| | MT-Bench confirm | MultiPref test |
|---|---|---|
| Agreement when confident (bar 90%) | 90.6% | 90.0% |
| Items it is confident on (bar 50%) | 62.4% | 36.6% |
| Average calibration gap, mapped (bar 0.10) | 0.063 | 0.050 |
| Same pick when answer order is swapped (bar 90%) | 91.1% | 82.1% |
| Pick flips when asked again (bar 5%) | 4.8% | 5.8% |
| Human ties it caught | 10 of 76 | 45 of 294 |
| Verdict | GO under the revised calibration bar | NO-GO, 2 of 5 |

## Uses, in order of value

### 1. Decide how many raters each item gets

Every incoming comparison is scored by the judge first, with both answer
orders and three repeats. That costs about $0.0003 per item at today's prices.

- **Confident and stable** (raw confidence ≥ 0.90 and the same pick in both
  orders): send to **2 raters** as a confirmation. If both agree with the
  judge, the item is done. If either disagrees, escalate to the full panel.
- **Everything else**: send to the **full panel** (e.g. 5 raters).

This is illustrative, assuming a 5-rater default. It saves about 35–37% of rater
judgments on MT-Bench-like work and about 22% on everyday prompts. Every
delivered label is still a human label. The judge only changes how many
humans look.

Never ship judge-only labels as human preference data. A 10% error rate on
"confident" items is fine for routing and not fine as ground truth.

### 2. Rater quality control

Items where the judge is confident and stable, and the human majority agrees
with it, make good hidden gold checks. A rater who disagrees with that
consensus far more often than peers gets reviewed.

Do this per rater over many items, never on a single disagreement. The humans
also showed position bias: 66% of MultiPref A-or-B votes went to the second
response shown. So randomise answer order for raters too, and track each
rater's lean.

### 3. Item triage

Some items are probably ambiguous prompts, not rater errors:

- the judge flips when the answer order is swapped;
- the humans split 2-2;
- the reviewers label the item "question unclear".

Send these to item review (rewrite, drop, or deliberately collect more votes)
instead of paying for more votes blindly.

### 4. Disagreement review

When the judge is confident and the human majority disagrees, Claude (Opus
5.5) reviews the item and labels who is likely wrong. Claude Fable 5.1 agreed
with Opus on 14 of 21 such items, so treat reviewer labels as a queue order,
not a verdict. Mike's spot-check of 20 reviews will set how far to trust them.
It is still pending.

### 5. Customer-facing metadata (optional)

Each delivered record can carry the judge's calibrated probability as
metadata, as in `enriched.jsonl`: a `judge_version`, never the vendor or
model.

Only do this with a calibration map fitted on a dev slice of that customer's
own data. The raw probabilities are overconfident: the average gap was 0.123
on MultiPref before mapping and 0.050 after.

## Guardrails for any deployment

- **Calibrate per domain.** Fit the isotonic map on a 20% dev slice of each
  new customer or domain before trusting the probabilities. Confidence did not
  carry over from MT-Bench to everyday prompts.
- **Preregister the bars before the data.** Write `PREREGISTRATION.md` and
  any amendments before scoring. Report the old bar next to any revised one.
- **Watch order stability.** On everyday prompts the judge changed its pick
  when the order was swapped on 18% of items. Always score both orders and
  route only on items where both orders agree.
- **Don't route ties.** The judge almost never says "about the same". Tasks
  where ties matter need the full panel. Rewording the rubric moved ties
  caught from 13 to 16 of 53, which is noise (`experiments/tie_wording`).
- **Keep provenance.** Every label records whether it came from the
  confirmation path or the full panel.

## Not yet known

- **Real QuestionPro rater data.** Both datasets are public. The next test
  should be a few hundred real items with several raters each, under the same
  preregistration process.
- **Whether a structural tie fix works.** For example, rating each reply on
  its own and calling a tie when the scores are close.
- **How far to trust Claude's disagreement labels.** This waits on Mike's
  spot-check.
