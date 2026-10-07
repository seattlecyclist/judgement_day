# judgement_day

Pilot for QP Judgement: does an AI judge's probability, added to each human preference item, agree with the human majority well enough to route rater spend and flag bad items?

The plan, metrics and go / no-go bars are in the AI Judge Pilot Plan doc. This repo runs the desk pilot on public data.

## Setup

```sh
bundle install
git config core.hooksPath .githooks   # blocks commits that look like they contain keys
bundle exec rake                      # tests, no network or keys needed
```

Keys are read at run time and never stored. Each one comes from an env var if set, otherwise from a shell function in your profile:

| Use | Env var | Shell function |
| --- | --- | --- |
| AI judge | `JD_JUDGE_API_KEY` | `typesafe-key` |
| Disagreement reviews | `ANTHROPIC_API_KEY` | `anthropic-key` |

## Running the pilot

```sh
bin/jd fetch                    # download MT-Bench human judgments, build items with 2+ votes
bin/jd score --preset smoke1    # 20 items, one order, capped at $1
bin/jd score --preset smoke2    # 50 items, both orders, capped at $1
bin/jd score --preset full      # 500 items, both orders, 3 repeats, capped at $5
bin/jd review --run full        # Claude reviews confident disagreements, capped at $10
bin/jd spotcheck list           # the 20 reviews waiting for Mike's check
bin/jd spotcheck add ID --verdict agree --note "..."
bin/jd spend
```

Every judge response is cached in `data/cache/`, so `bin/jd report --run NAME` and reruns after a fix are free. Each run stops before any call that could cross its cap.

## Outputs

- `data/runs/<run>/report.json`: threshold sweep, calibration, order and repeat stability, results by category, go / no-go checks.
- `data/runs/<run>/enriched.jsonl`: one record per item in the customer-facing format. The `ai_judge` block names only `judge_version`, never the model or vendor.
- `reviews/disagreements.jsonl`: append-only log of Claude's reviews and Mike's spot-checks. Never edit or delete lines; corrections are new records.

## Data

[MT-Bench human judgments](https://huggingface.co/datasets/lmsys/mt_bench_human_judgments) by LMSYS, CC-BY-4.0. Raw data is downloaded to `data/raw/` and not committed.
