# Learnings from the AI judge desk pilot

Recorded 2026-10-07. Newest results first in each section. Links point to
the commits and files that hold the evidence.

## Results

- **MT-Bench, first full run (bug present): NO-GO, 2 of 5.** Superseded; see
  the turn bug below.
- **MT-Bench full rerun: 4 of 5.** Agreement 92.3%, coverage 51.3%, order
  91.0%, repeat flips 4.0%. Calibration missed: worst bin 0.260, average gap
  0.114.
- **MT-Bench confirmation, locked setup on 461 unused items: 5 of 5 under the
  revised calibration bar, 4 of 5 under the original one** (worst bin 0.142).
  Agreement 90.6% (CI about 87–94%), coverage 62.4%.
- **MultiPref, preregistered, 1,588 test items: NO-GO, 2 of 5.**
  - Passed: agreement 90.0% (CI 87–92%), calibration 0.050.
  - Missed: coverage 36.6%, order 82.1%, repeat flips 5.8%.
- **Total spend for the whole pilot: $3.61** (`bin/jd spend`). Claude reviews
  were about two-thirds of it. Judge calls cost about $0.05–0.06 per 1,000.

## About the judge

1. **When it is confident it is right about 90% of the time, in both
   domains.** That held against experts alone and regular raters alone (91%
   each on MultiPref), and rose to 93% where 3 or more of 4 raters agreed.
2. **How often it is confident depends on the domain.** It was confident on
   60% of MT-Bench items and 37% of everyday prompts. Everyday comparisons are
   closer calls, and order stability fell from 91% to 82%.
3. **Ties are its blind spot.** It caught 13–22% of human ties across runs.
   Telling it in the rubric to call ties barely helped (13 to 16 of 53,
   `experiments/tie_wording`). A temperature plus tie-bias remap caught more
   ties, but broke order and repeat stability. A real fix probably needs a
   different question design.
4. **Its raw probabilities are overconfident below 0.9.** A per-domain
   isotonic map fixes this out of sample (0.123 down to 0.050 on MultiPref).
   The map never changes a pick, so stability is unaffected. Fit it per
   domain: MT-Bench confidence did not transfer.
5. **Agreement measured against a majority of two votes is noisy.** The
   judge agreed with unanimous raters 94% of the time and with split raters
   68%.

## About the data

1. **Check what the humans actually saw.** MT-Bench rows carry the full
   two-turn conversation even for turn-1 votes. The first run judged and
   reviewed turn-1 items on replies nobody voted on. Trimming to the voted
   turn moved agreement from 82% to 92% (`7a38ae6`). It was found only
   because a spot-check page showed the replies side by side.
2. **Humans have position bias too.** 66% of MultiPref A-or-B votes went to
   the second response.
3. **MultiPref was the only public dataset that fit.** It has everyday
   prompts, 4 independent votes per item and an explicit tie option.
   HelpSteer2 and HelpSteer3 have no tie votes, and HelpSteer3 releases only
   the most-agreeing annotations. Chatbot Arena has one vote per pair.
   AlpacaFarm is non-commercial.

## About method

1. **Preregister before touching data, and amend only before scoring.** The
   MT-Bench calibration bar moved from worst-bin to average gap after the full
   run missed it. The bar is defensible (worst-bin at a few hundred items is
   mostly noise), but it made the MT-Bench "GO" arguable. MultiPref was
   preregistered (`PREREGISTRATION.md`) and its NO-GO is not arguable.
2. **Report the old bar next to any revised bar**, and say plainly which rules
   changed and when.
3. **Small holdouts give wide intervals.** 36 of 39 is "92%" with about ±8
   points. Report Wilson intervals, and do not celebrate passes that sit on
   the bar.
4. **An adoption rule needs a minimum effect size.** The tie-wording rule
   passed on a +3/53 change that is noise.
5. **Claude reviewers disagree with each other.** Opus 5.5 and Fable 5.1 gave
   the same label on 14 of 21 disagreements, and before the turn fix only 4 of
   12 turn-1 items. Treat review labels as a queue order until a human
   spot-check calibrates them.

## About running it

1. **Cache every paid call by request content and data version.** Bug-fix
   reruns, report regeneration and restarts at a different worker count were
   then free. Restarting MultiPref from 8 to 16 workers lost nothing.
2. **The Hugging Face rows API rate-limits** (HTTP 429) after a few thousand
   rows. Back off exponentially and pause between pages.
3. **Set the locale or force UTF-8.** With no `LANG`, Ruby read data as
   US-ASCII and crashed. Reads are now explicit UTF-8 (`87f2c63`).
4. **Paid runs from a freshly cloned repo can be blocked** by the auto-mode
   safety check until the owner authorises them in the thread.
5. **Parallel sessions duplicated work four times.** The coordinator and the
   machine session both built the turn fix, the calibration experiment, the
   locked setup and the preregistration. Assign an owner to each task before
   starting, and post a one-line claim before writing code.
6. **Make human checks fast, never automate them.** The spot-check page puts
   the reviewers' disagreements first, adds a plain-English summary of each
   item, and emits `bin/jd spotcheck add` commands. Claude did not do the spot
   check itself.
7. **Watch for silent drops in Ruby.** A non-gating metric used `filter_map`,
   which drops `false`, so "agreement vs experts" read 100%. It was caught by
   checking a suspicious number before reporting, and is now covered by a
   test.

## Open items

- Mike's spot-check of the 20 Opus reviews. `bin/jd spotcheck list` shows
  them, and `tools/spotcheck` builds the page.
- A test on real QuestionPro rater data, under the same preregistration
  process.
- A structural tie experiment.
