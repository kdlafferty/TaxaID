# Screen run log, 2026-10-04 to 2026-10-08 (archive)

Split out of `REENTRY_PROMPT_prepublication_screen.md` on 2026-10-11, unedited.
These are that document's sections 7c through 7o -- merge ledgers, resolved
investigations and end-of-session state from the CalIntertidal R1009 work. They
are a record of what was done and why, not instructions: nothing here is an open
item, and a session picking up the screen does not need to read it first.

The live screen is the other document. Its section 7 (Stage B verification)
stayed there, because the passes it defines are still the screen's method.

## What is in here

| Section | Subject |
|---|---|
| 7c, 7d, 7h | Merge ledgers for the memory and network-robustness work |
| 7e | 12S/18S/COI assignments are not stable (2026-10-06) |
| 7f, 7g | Accession-screen and `.is_unreferenced_type()` findings |
| 7i | Does a consensus call depend on its frame-mates (open at the time) |
| 7j, 7k | The full run on `01feb65`, and its peak moving +1.37 GB |
| 7l | G5+G6 (a) merged and installed at `b0ee48c` |
| 7m, 7n | The guard-line threshold audit; resolved-only support |
| 7o | State at session end, 2026-10-08 |

---

## 7c. Merge ledger -- 2026-10-04 (memory work for the COI retrain)

All verified on the MERGE, not the branch: suite + CI-equivalent
`rcmdcheck(args = c("--no-manual","--as-cran"))` + README inventory recomputed
from the tree. TaxaLikely installed after each merge that changed `R/`.

| merge | branch @ tip | what |
|---|---|---|
| `629b40e` | `region-match` @ `100c1f4` | NEW EXPORT `match_reference_region()` -- maintainer approved directly |
| `0584354` | `rowblock-pairs` @ `38a0a3c` | row-blocked pair extraction, internal |
| `7e772f1` | `region-match-pair` @ `5da0492` | docs only: matching and augmentation are a PAIR |
| `b3acd7f` | `bind-ranks` @ `b61e4cb` | chunked retention, single bind, `match()` ranks, duplicate-id check |
| `1ffe11d` | `bind-ranks-note` @ `ec9c342` | docs only: chunk size is a target, not a cap |

**Why the first memory fix was not enough, and what found the real cost.** The
retrain died at 19 GB against an 18 GB watcher. Row-blocking `which(dist < max
& row != col)` saved only ~0.7 GB at 12k representatives. The owner's
**stage breakdown** -- not the fix -- located the cost in the final
`best_per_partner` pass (~245 B/pair, ~9-11 GB projected at full COI). Record
this ordering: measuring the stages was worth more than the first optimisation.

**Chunking a retention pass is exact only when cut on the grouping key.**
`best_per_partner` decides within each `(x, stratum)` group where `x` is the
QUERY side, so chunks cut between `id_x` VALUES keep every group whole and
reproduce the one-pass result exactly; ties resolve on coverage then the tie
vector, by value rather than encounter order, so chunk order cannot change the
outcome either. A cut at ROW COUNTS splits a group and silently drops the
global best two -- no error, just different training pairs. The test asserts a
naive row cut at 13 gives a DIFFERENT, WRONG answer, which is the right shape:
aim the test at the silent failure, not at the correct answer.

**`chunk_rows` is a target, not a hard cap** -- chunks hold equal numbers of
distinct `id_x`, not equal rows, so a query id with many pairs overshoots it.
Lever: `options(TaxaLikely.retention_chunk_rows = 5e5)` (755 MB vs 1,037 at the
2M default, 1,200 genera). The CalIntertidal full run launched 09:16 PDT with
5e5 set up front.

**Measured, 1,200-genus real COI subset, 3.49M pairs:** stage heap max 1,214 MB
unchunked / 1,037 at 2M / 755 at 0.5M; identical sorted-table digests old vs
new at 300 and 1,200 genera.

**The duplicate-`composite_id` thread, and a claim I withdrew.** I asked for a
duplicate-key test case because `match()` keeps only the first match where
`left_join` duplicates rows. A peer reported that duplicates reach the
alignment and fabricate `p_match = 1` within-species pairs; I built a
three-part bias synthesis on that WITHOUT opening the file and had to withdraw
it. `build_sequence.R:526` already runs
`distinct(composite_id, .keep_all = TRUE)` in step 1, before alignment at step
3, so no production matrix was ever affected. The real defect is narrower and
sharper: `distinct()` keeps the FIRST row, so when copies DISAGREE the
surviving values depended on the ROW ORDER of `reference_df` rather than its
content -- the "a result must depend only on its inputs" family. Now an error
on disagreement, a message on agreement; 12S 4 agreeing ids, COI 314, 18S none,
so no real output changes. **Lesson: "check the thing, not a proxy" applies to
a teammate's description of code exactly as it does to a test's name.**

**Verification timings, measured** (one package, TaxaLikely at 34 test files /
1,810 assertions): full verify 4-5 min with the `rcmdcheck` as the long pole;
`R CMD INSTALL --no-docs -l` **2 seconds**; post-install behaviour check plus
TaxaWizard's pack guard 2-3 min; SHA to merged-and-installed ~12 min, achieved
in 7. The install being 2 s is the useful fact: there is never a speed reason
to jump the reinstall gate.

## 7d. Merge ledger -- 2026-10-05/06 (training memory + network robustness)

| merge | branch @ tip | what |
|---|---|---|
| `e5e9636` | `train-blocks` @ `11316e1` | blocked curve collapse + training-data prep |
| `6c83ced` | `train-blocks-note` @ `040252c` | docs: why the per-block `N_Obs` sum is exact |
| `ce2bf22` | `ncbi-timeout` @ `dabf5f0` | progress-based aborts on all 21 remote calls |

**All four memory stages are now merged and installed** -- matrix `which()`,
retention pass, curve collapse, training prep. Full-COI training measured at
7.66 GB peak where it was previously killed at 17.2 GB. The pattern worth
keeping: each stage was found by MEASURING the stages, not by guessing which
was next, and the first fix (row-blocking) saved only ~0.7 GB of a >19 GB peak.

**Curve blocking is exact only because stage 2 runs ONCE.** Stage 2 groups by
TAXON (species/genus/family), not by query, so blocking it by `id_x` would give
each block a PARTIAL `k` and `n`; the Jeffreys mean `(k + 1/2)/(n + 1)` is not
additive and `.equal_weighted_pooled()` would give a split species double
weight -- plausible curves, quietly wrong, setting the confusion-risk values.
`.id_blocks()` also sorts with `method = "radix"` (C-locale, so block
membership does not shift with the machine's locale) and preserves within-block
row order, which is what makes `slice_max(with_ties = FALSE)` reproduce.

**RETRY WITHOUT A TIMEOUT IS NOT PROTECTION.** `.retry_fetch()` had 3 attempts
with backoff, but it catches an ERROR and a hung socket never errors, so it
never fired -- a network change hung a run on a dead socket. Before `ce2bf22`,
`grep timeout` over all of TaxaLikely/R returned nothing. And the fix is NOT a
single total timeout: curl's TIMEOUT is total request time, so a value low
enough to catch a dead socket also kills healthy large fetches, and the retry
then burns three attempts on the same doomed request. **What separates the two
cases is PROGRESS, not elapsed time**: `connecttimeout` 30 s,
`low_speed_limit` 1024 B/s over `low_speed_time` 60 s, 1800 s total as a
backstop, all option-controlled.

**Still open from the pre-flight audit** (2026-10-05, package side):
- taxid resolution is UNCACHED and runs before the cache check (`fetch.R:1465`
  vs `:1509`), so a fully cached run still pays ~2,830 live esearches, ~35 min.
  Deferred; safe only because Stage B makes no fetch calls. The risk in fixing
  it is the CACHE KEY, which must encode taxon AND lineage scope.
- `sel_params` version stamp + which-case message: rides with the next
  `fetch.R` change. Today one message covers capped, differently-blacklisted
  and never-stamped, which have very different costs.
- The `sel_params` gate (`8ee72a0`, merged `c9e0a76` 2026-09-28) cost
  CalIntertidal 18S an ~8 h refetch of all 2,830 genera. NO SAFE MIGRATION
  existed: the workflow writes capped (lineage repair, `max_per_species = 20`)
  and uncapped fetches into the SAME cache dir, and `blacklist_regex` is not
  recoverable from file content.
- **COI likelihoods below 75 are extrapolated for OBSERVED hits too** -- a
  SEPARATE, pre-existing condition, not a consequence of the restoration
  defect. `build_sequence_matrix(max_dist = 0.25)` means no reference pair
  below `p_match` 75 ever trained H1/H2/H3, and 12.8% of COI ESV@Site (2,366)
  have their best observed hit in that untrained tail. Consequence is mostly
  confined to coarse ranks -- those rows take phylum/class consensus and only
  11 have a sub-75 named-species R2 winner -- so this is a scope note to
  document rather than a blocker. The lever if wanted is `max_dist`: training
  on more distant pairs extends the calibrated range, at a matrix cost the
  2026-10-05/06 memory work has made affordable.
- **`max_per_genus` default fragility**: `976639d` changed the default NULL ->
  500L, and because it is part of the cache key the workflow's explicit
  `max_per_genus = NULL` is the only thing keeping ~21 h of COI plus the 12S
  cache valid, protected by a comment. "The same workflow arguments" is NOT a
  safe statement across package versions.

## 7e. 12S/18S/COI ASSIGNMENTS ARE NOT STABLE (2026-10-06)

Three outstanding items, all awaiting the maintainer, and they do NOT need the
same kind of re-run:
1. **Round 2 circular boost** of unreferenced/ring rows -- MERGED as item b, `4acf4d3`; see 7h.
2. **`restore_suppressed_candidates()` score imputation** -- changes
   ASSIGNMENTS. Levels 1-3 impute a restored congener's QUERY score as the
   median reference-vs-reference `p_match`, which is only valid when the query
   matches its anchor almost exactly. Measured: 568 18S and 577 12S
   observations carry a restored row imputed ABOVE its anchor (excess median
   3.7, max 29.3 points for 18S), and 279 + 256 of those are the TOP
   likelihood. Worked case: 18S_ESV_026656, every real hit 77-78%, restored
   *Porphyra mumfordii* imputed at 97.18 and winning at likelihood 1.0, from a
   reference covering 43% of the region.
   **COI IS THE WORST-AFFECTED MARKER, not 18S** (counts on the final files,
   2026-10-06): inflated restored rows are the Round 2 winner for 403 COI
   ESV@Site against 233 12S and 190 18S, and drive SPECIES-LEVEL consensus
   calls for 283 COI against 67 12S and 20 18S. COI adds 1,168 observations at
   likelihood level with a median excess of 8.7 points. Any statement scoped to
   "12S and 18S" understates this -- an earlier version of this section did.
   **AND THE REACH IS WIDER THAN THE WINNER COUNTS** (measured 2026-10-06, 300
   COI observations containing an inflated row): as-is vs corrected changes the
   TOP-LIKELIHOOD hypothesis in **227 of 300**, while the restored row itself
   was the top in only 10. An inflated restored row becomes the observation's
   BEST SCORE, which moves the gap feature and the H2/H3 anchor for EVERY other
   candidate -- so one bad imputed score distorts the whole observation's
   feature set, not just its own row. Counting "observations whose R2 winner is
   an inflated row" (403 COI / 233 12S / 190 18S) therefore UNDERSTATES the
   exposure by roughly an order of magnitude; the right denominator is
   observations CONTAINING an inflated row: **1,168 COI / 577 12S / 568 18S**
   (the 1,971 / 1,049 / 1,359 figures are inflated ROWS, several per
   observation -- an earlier version of this section conflated the two). Any
   before/after must report on the observation denominator.
   **The anchor IS the observation's best observed score**, verified in code:
   `score_collapse.R:749` takes `anchor_idx <- which.max(sc_vec)`. So the
   invariant below really does bound the imputed score by the best MEASURED
   evidence, not merely by some anchor's score.
   **The invariant the fix establishes**, worth asserting in code rather than
   only computing: since `r <= 100`, `a - (100 - r) <= a`, so AN IMPUTED SCORE
   CAN NEVER EXCEED THE OBSERVATION'S BEST OBSERVED SCORE. That is the property
   that was violated, and a defensive assertion on it would catch any future
   formula change that broke it again.
   **Sub-floor handling, measured**: under option 2 (extrapolate and flag) the
   sub-floor COI restored rows are nearly weightless -- median likelihood share
   0, max 0.067, 15 of 564 above 1% -- and option 2 vs 3 changes the top
   hypothesis in only 13 of 300. So the choice is mostly bookkeeping, and
   option 3 (DROP below the training floor, with a
   `restored_below_training_floor` reason code) is the honest form. Dropping is
   not neutral either: it redistributes the candidate's mass (top share rises
   by median 0, max 0.71).
   Agreed fix: `anchor_score - (100 - ref_ref_identity)`, a no-op when the
   anchor match is 100%. **Describe it as a conservative DATA-DERIVED LOWER
   ESTIMATE, not a triangle-inequality proof**: percent identity over pairwise
   OVERLAPS is not a metric (three different overlap regions, each normalised
   over its own with `includeTerminalGaps = FALSE`), so the bound CAN be
   violated -- partial coverage, as in the worked case, is exactly where. It
   does NOT contradict the file header, which rejected a CONSTANT delta; this
   delta is measured.
   **Proposal written and code-checked**: `ecosystem_docs/PROPOSAL_restore_imputation_fix_2026_10_06.md`,
   five parts -- corrected formula; asserted invariant (with a test that the
   assertion FIRES on a constructed violation); drop-below-training-floor with
   `restored_below_training_floor`; all-NA anchor dropped as unscoreable with
   `restored_no_anchor_score` (0 cases in tonight's data, handled anyway --
   that zero is a property of CURRENT data, not a guarantee, so the handling
   must not be removed as dead code later); and a before/after on all
   observations containing an inflated row, labelled imputation-only. Awaiting
   the maintainer. Package review verified the mechanism, the anchor
   definition and the training floor against the code.
   **PART 1 OF THAT PROPOSAL IS OVERTURNED BY MEASUREMENT (2026-10-06, 21:12),
   and the error was mine as much as anyone's.** Verified in code:
   `regional_overlap.R:286` aligns CANDIDATE to ANCHOR (`pid(aln)` at :309),
   and :241 aligns the query only to the ANCHOR to derive a position range --
   so NO level has ever aligned the query to the candidate, and there was never
   a measured query-to-candidate score. Measured directly (region-trimmed refs,
   >= 80% query coverage):
   - today's imputation is ACCURATE when not inflated, MAE 0.94-1.27;
   - the proposed `anchor - (100 - ref_ref)` OVER-PENALISES, MAE 1.48-4.59, and
     is WORSE THAN TODAY on the rows it targeted (inflated COI: 7.02 vs 5.08);
   - `min(today, anchor)` is the best cheap estimator, MAE 0.94-1.99.
   **The ceiling-at-anchor invariant is empirically FALSE as a truth claim**: a
   restored congener's true identity beats the best retained hit in 58% of 18S
   pairs, because suppression is not about identity. It is defensible ONLY as a
   conservative constraint on an unverifiable ESTIMATE -- so ceiling AND
   assertion belong at the IMPUTATION SITE only, with a test that a measured
   score above the anchor passes untouched. I had argued it as a general
   property; that was wrong.
   Revised design: MEASURE query vs candidate directly (0 restored rows lack a
   placed region reference; ~22 min single-core total), fall back only where
   query coverage < 80% (4-22% of pairs), bound the fallback only, keep+flag
   below the 75% floor.
   **Open requirement before it lands**: the measured score must be VALIDATED
   against `seq_matrix`'s own `p_match` rather than asserted equal to it. Level
   4's comment claims `pwalign::pid()` PID1 is on the same scale, citing ONE
   case (F. parvipinnis/F. lima, 96.43%), but training `p_match` comes from
   `DECIPHER::DistanceMatrix(includeTerminalGaps = FALSE)`. Compute both for
   pairs ALREADY IN `seq_matrix` and report the offset; a systematic offset
   means restoration scores are read against densities trained on a different
   scale.
   **The lesson**: I checked that formula's ARITHMETIC and its consistency with
   the file header, and never asked whether it was ACCURATE. Only the
   before/after-before-merging requirement caught it.

## 7h. Merge ledger -- the approved four-item sequence (2026-10-06/07)

Maintainer approved the full list, then went to bed with "you can work on
auto". ONE install after all four are merged, only with zero R running. Each
required a REAL before/after in its review response.

| item | merge | branch @ tip | what |
|---|---|---|---|
| d1 | `8cc0c36` | `upfc-memory` @ `904196d` | narrow-merge row assembly, exact |
| b | `4acf4d3` | `upf-referenced-only` @ `043dd0e` | soft confirmation excludes unreferenced relatives |
| d2(ii) | `46cea96` | `pc-index-split` @ `9b8aeaa` | per-observation chunks from one row-index split, exact |
| a | PENDING | `restore-measured` | measured-first restoration + calibration |

**d1 was merged AND INSTALLED before the hold arrived** (TaxaAssign, build
2026-10-07 04:01:05 UTC), so the installed state is already ahead of the
"one install at the end" plan. Harmless: items b and d2(ii) touch TaxaAssign
too, so the final pass reinstalls it anyway.

**b is the finding, not the fix**: rows raised 1,552,495 -> 58,300, with
unreferenced-relative raising going 1,493,171 -> ZERO while referenced raising
barely moves (59,324 -> 58,300). **96% of all prior-raising was driven by rows
that exist BECAUSE no reference supports them.** The mechanism is not reduced;
a circularity that was doing almost all of the work is removed.

**d2(ii) differs from the rest of the week's memory work in two ways**: the gain
is COMPUTE (CPU 343 -> 219 s on an idle machine), not relieved pressure, and
MAXIMUM RESIDENT ACTUALLY DROPS (3.85 -> 2.30 GB) where `upfc-memory`'s did
not move at all -- so this is the one the tree watcher will see.

**The review-response file conflicts every time two branches touch it.** b and
d2(ii) both appended a dated section at the shared end-of-file insertion point;
resolved by keeping both. DATED HEADINGS DO NOT PREVENT THIS -- I claimed
earlier in the week that they had, when that pair had merely written to
different SECTIONS (894 and 1212). Headings make the resolution trivial and
unambiguous; the shared insertion point still collides.

**Standing decision rule while the maintainer sleeps**: merge what passes the
full standard, HOLD what does not. The standard does not move -- suite,
CI-equivalent rcmdcheck, inventory recomputed from the tree, exports diff, and
a real before/after. "Work on auto" authorises proceeding without asking, not
lowering the bar on the maintainer's behalf.

## 7j. The full run on `01feb65` COMPLETED (2026-10-07)

Started 07:55, **finished 12:47:14 with rc 0** -- the first full run to
complete after the four memory stages, the network-timeout fix and the
four-item assignment sequence. Attempts 1-6 had all been killed by the tree
watcher or a workflow defect.

**The h1-spread re-measure has been DONE ONCE and came back clean.** posterior
math's 2026-10-07 morning measurement (item c) found the adopted spread SAFE:
**0 risky flips**. So the standing caveat in 7e is partly discharged -- the
defaults were fitted on data carrying two within-species biases, but the
measurement says the consequence is nil. What remains is a FOLLOW-UP re-measure
after C1 lands, because C1 changes the calibration machinery itself.

**Next run is gated on**: C1 (TaxaLikely, query-noise calibration from observed
rows only), G3 and G1 (TaxaAssign, Round 2 raises only inside the R1
likelihood-only credible node; never raise rows with no occurrence record),
plus workflow-only P1-P5 from the audit. `cross-phylum` (`6cd806d`) stays
post-run.

**ONE PRINCIPLE, NOW FOUR INSTANCES, found separately by two sessions:
DO NOT LET WHAT IS NOT AN OBSERVATION BEHAVE LIKE ONE.**
- item b (`4acf4d3`): unreferenced relatives no longer lend cross-observation
  support nor receive a boost -- 96% of all prior-raising was theirs;
- G3: raising confined to the R1 likelihood-only credible node;
- G1: rows with no occurrence record are never raised;
- C1: non-observed rows no longer enter the query-noise calibration.
To be written into the review responses as a family rather than four unrelated
fixes, so whoever meets the fifth instance recognises it.

**PER-STAGE TREE PEAKS, measured** (`run_next_2026-10-07_0755.stages` +
`_stage_peaks.tsv`), minutes / GB:

| Stage | min | GB |
|---|---|---|
| COI prep (frozen) | 1.1 | 8.13 |
| **COI restoration+join** | 50.9 | **15.92 = RUN PEAK** |
| COI training | 16.1 | 12.40 |
| COI evaluate (parallel) | 107.8 | 7.14 |
| 12S restoration / training / evaluate | 6.1 / 0.1 / 11.6 | 3.71 / 3.81 / 3.57 |
| 18S restoration / training / evaluate | 1.6 / 0.7 / 12.7 | 4.16 / 5.08 / 3.77 |
| Section 8 Round 1 | 34.1 | 15.17 |
| Section 8 U update (fresh) | 14.4 | 10.78 |
| Section 8 W2 restore COI / P post-update / X robust | 1.2 / 10.6 / 10.7 | 7.61 / 5.33 / 5.52 |

**THE MEMORY WORK SUCCEEDED AND THE PEAK HAS MOVED.** Training, the stage that
killed attempt 3 at >17.2 GB, is now 12.40 GB -- the THIRD largest. The peak is
COI restoration+join at 15.92 GB, which is the existing 34.1M-pair accession
index plus join, a stage nobody has optimised and NOT fix (a). Round 1 is
second at 15.17. So the profile-first item for any next round is the accession
index and join.

**MY PROJECTION WAS 13% OPTIMISTIC, and for the reason I had flagged as
unverified.** I projected ~11 GB for training (3.3 parent + 7.7 child) and
noted the parent-baseline assumption was "likely but unverified". Actual
training peak 12.40 GB, so the parent held about 4.7 GB rather than 3.3. The
caveat was the right one to state and the error was in the direction it warned
about.

**Headroom is about 4 GB against the 20 GB cap**, at two stages only: COI
restoration+join and Round 1. Anything added at either needs a memory check
first. Note that C1 (training-path calibration) and G1/G3 (Round 2 raising,
the U and P stages at 10.78 and 5.33) touch NEITHER peak stage, so they should
not move the ceiling.

**The time lever is separate from the memory lever**: COI evaluate is 107.8 of
roughly 250 total minutes at only 7.14 GB, so it is time-bound, not
memory-bound. Shortening the run means parallelism there, not memory work.

## 7k. The run peak MOVED +1.37 GB -- RESOLVED as variance (2026-10-07)

Morning run (main `01feb65`): COI names+drop+restoration+guard+join peaked at
**15.92 GB** in 50.9 min. Evening run (main `7b36dca`, with C1 and G1/G3):
**17.29 GB** in 55.6 min, SAME stage, identical inputs, matrix reused. Headroom
at the run's peak stage is now about **2.7 GB under the 20 GB cap**.

**TWO EXPLANATIONS, OPPOSITE IMPLICATIONS, NOT YET DISTINGUISHED:**
1. Run-to-run heap variance in the 34.1M-pair index/join -- GC timing and
   fragmentation do move peak RSS -- in which case the ceiling is unchanged and
   this is the noise band, itself worth knowing.
2. **C1's re-admitted candidates.** C1 re-admits 2,392 of the 9,479 gated
   observed COI candidates. Its CODE is not in that stage, but it changes the
   SIZE of the candidate set, and more rows cost memory wherever those rows
   flow -- a join especially. If so the ceiling has MOVED FOR A REASON and 2.7
   GB is the new normal.

**RESOLVED: RUN-TO-RUN VARIANCE.** My C1 hypothesis is refuted on BOTH
grounds. Empirically, that stage's row counts are IDENTICAL between the runs --
restoration 205,552 -> 215,139 in both, dropped-hit replacement 446 dropped
rows -> 520 candidate rows across 148 observations in both, matrix reused at
34,101,480 pairs. Structurally, C1 cannot reach that stage: calibration runs
AFTER training, and the 2,392 re-admitted candidates are ones the H1 outlier
gate now passes inside `evaluate_likelihoods` (likelihood > 0 instead of 0),
downstream of names+drop+restoration+guard+join -- and they were already rows
in the match object in both runs.

**CONSEQUENCE WORTH PLANNING AGAINST: a ~1.4 GB variance band at a stage with
~2.7 GB headroom means the effective ceiling is nearer 18.7 GB than 17.29.**
Half the remaining headroom is consumed by the noise, so this stage should be
treated as being at about 18.7 GB for any decision about adding work there --
one bad draw, not a trend, is enough to trip a 20 GB cap.

**THE DISCRIMINATOR, KEPT because it is the right test to repeat:** row counts,
not memory. Compare that stage's input and
output row counts between the two runs. Identical inputs and a reused matrix
mean the candidate set is the only thing that should differ; roughly 2,392 more
COI candidate rows means C1, matching counts mean variance. Derivable from the
stage log or the saved outputs, so no new run is needed. **Do not record
"variance" until this is checked** -- a specific mechanism with a known
magnitude is sitting right there, and accepting the plausible explanation
without measuring is the shape that produced the five-agreeing-CV-methods
episode and the restore-imputation formula endorsed on arithmetic alone.

**EITHER WAY THIS IS NOW THE STAGE TO PROFILE FIRST.** It is the run peak, it
has the least headroom, and it is the ONE stage this week's four memory fixes
never touched. region_matched_references already identified the 34.1M-pair
accession index plus join as the cost and nobody has measured inside it. If the
next round of memory work has a single target, this is it.

## 7i. OPEN INVESTIGATION: does a consensus call depend on its FRAME-MATES? (2026-10-07)

Unconfirmed, and if confirmed it outranks everything else in 7e-7h. Found by
posterior math while validating `cross_phylum_eps`: 2 COI sipunculan ORDER
calls at Jalama Beach (Golfingiiformes) fired the cross-phylum rule under v1
(frame = 24,739 observations) but NOT under v2 (frame = 109). For an
order-level call both versions fire on the same condition, so THE PHYLUM VALUES
MUST HAVE DIFFERED BETWEEN RUNS.

Refuted already: v1 rewriting the taxonomy cache (all 4,926 files
byte-identical, mtimes are the copy time).

Remaining lead: `lookup_missing_taxonomy()` or harmonisation may fill a name's
phylum FRAME-WIDE, so what one observation resolves to depends on which OTHER
observations share the input. That is the "a result must depend only on its
inputs" class -- see [[reference_result_must_depend_only_on_its_inputs]] -- and
it would mean every chunked call (per Site, per marker, per batch) disagrees
with the whole, regardless of how correct the rule is.

**THE EXPERIMENT MUST VARY ONLY THE FRAME.** Comparing v1-on-24,739 against
v2-on-109 confounds code version with frame size. Run V2 ALONE on the 2
observations, then on the 109, then on the full 24,739. Differing calls prove
frame dependence under one code version; identical calls send you back to the
v1-v2 difference. Same 3 GB load, one variable.

**A SECOND, INDEPENDENT DEFECT IN THE SAME LEAD.** Sipuncula is a known
backbone disagreement -- a phylum, or within Annelida. If `cross_phylum_eps`
compares PHYLUM NAME STRINGS, one lineage carrying two names is counted as two
phyla and the rule fires on an ambiguity that does not exist. That is a bug
whether or not the frame matters, and the fix is to compare RESOLVED LINEAGES.
Standing lesson: [[reference_homonym_name_is_not_a_key]] -- a bare-name query
once pulled 306K vertebrate sequences for a red alga.

**If frame dependence is confirmed**: taxonomy filling must be per-observation
or precomputed before the call, never frame-wide inside it, and the test that
pins it is an INVARIANCE test -- the same observation in a frame of 1 and a
frame of many must give an identical call. Worth adding regardless of the
outcome, since it is the only thing that stops the next frame-wide convenience
reintroducing this.

Deferred until after the full run: it needs a 3 GB posterior load, and doing
that beside a live production run risks a watcher trip.

## 7g. QUEUED for the maintainer: `.is_unreferenced_type()` gates the boost (2026-10-06)

Pre-existing, but `043dd0e` (item b) made it consequential. `.is_unreferenced_type()`
(`site_utils.R:437`) hardcodes `^unreferenced_(phylum|class|order|family|genus|species)$`
-- SIX ranks -- while `.RANK_LADDER` has SEVEN, including `kingdom`. Harmless
today: `.unreferenced_ring_rank()`'s `i > 1L` guard means a kingdom-level ring
cannot form, so the two agree in effect.

**Why it now matters**: that predicate used to drive reporting; after item b it
GATES WHETHER A ROW'S PRIOR CAN BE RAISED. Anything the regex misses returns
FALSE, i.e. TREATED AS REFERENCED, i.e. eligible for the circular boost again
-- silently. With rank-ring work active, one added rank re-opens it, and no
test notices unless its fixture happens to use the new rank.

**Agreed shape of the fix** (to the maintainer as its own item, not slipped in,
since the predicate is shared by SIX call sites):
1. Derive the pattern from `.RANK_LADDER`, keeping EXACT semantics at all six
   call sites -- `join_priors.R:80`, `:1372`, `:1610`,
   `posterior_consensus.R:807`, `update_prior_from_consensus.R:346`. A bare
   `^unreferenced_` prefix match was considered and REJECTED: it fails safe for
   the gate but broadens the predicate for five other callers, and `:1372`
   SELECTS ring rows rather than excluding them, where over-matching means
   acting on a row that is not a ring.
2. Only if the gate should fail safe independently, add a separate,
   deliberately permissive `.is_boost_ineligible()` used ONLY by
   `update_prior_from_consensus()`, so the difference is visible in the names.
3. A test ENUMERATING `unreferenced_<rank>` for EVERY ladder rank, so a ladder
   change fails loudly. Spot-checking two ranks cannot report an absent one.

Same 'derive, don't duplicate' lesson as `ring_codes` deriving from the model's
own `rank_system`.

## 7f. Accession screen drops references on OUT-OF-REGION evidence (2026-10-06)

Its own defect, not a symptom of restoration. 12S drop `AY279644` is **100%
*S. pulcher* on the MiFish region**, dropped for family-rank evidence elsewhere
in its 940 bp. That single drop leaves **41 12S ESVs with zero candidates, 32
of which match kept same-species references at >= 99%**. The screen is judging
a reference on sequence the amplicon never sees -- the same region-scoping
theme as `match_reference_region()`. The restoration fix's dropped-hit
replacement (an ESV whose only hits are dropped gets the species' kept placed
refs as candidates, measured; ~32 12S ESVs incl. sheephead, 2 18S) MITIGATES
the symptom; it does not address the screen. Needs the maintainer as a separate
item.

3. **h1-spread re-measure** -- a property of the TRAINING pairs, not of
   assignment. Needs a retrain and a measurement, NOT a full run, and its
   inputs are already merged and installed, so it can run in parallel.

Cheapest sequence: measure the spread now; build and verify 1 and 2; land both
with ONE install; then ONE full run. Landing 1 and 2 separately costs two
20 h cycles and yields two runs differing for two reasons.

## 7l. G5+G6 (a) MERGED+INSTALLED main b0ee48c -- acceptance exact (2026-10-08)

Kevin decided "G5+G6" (relayed verbatim by the coordinator; not heard directly
here). Posterior math is building both in TaxaAssign on `round2-g56`. On arrival
the cycle is the standard one: verify the merge, merge, install TaxaAssign only
behind the zero-R check, re-run TaxaAssign + TaxaWizard, regenerate
`llm_prompts/` only if the exported docs changed. G5/G6 add thresholds, so a new
argument is likely; check rather than assume.

### The verification script no longer gets copied

`scratchpad/verify_merge.sh <pin> <Pkg> <tag>` replaces the per-branch scripts.
The G4 vacuous run happened because each script was produced by `sed`-ing the
previous one and the pattern silently matched nothing, leaving a pin that was
already an ancestor of main; `git merge` then said "already up to date" with
exit 0 and the suite passed. There is now nothing to `sed`. Four anti-vacuity
guards, self-tested rather than merely written:

| condition | exit | tested |
|---|---|---|
| pin already an ancestor of main | 4 | yes, against `58c625a` |
| pin does not exist | 3 | yes |
| merge did not move HEAD | 5 | -- |
| merge changed no files | 6 | -- |
| dirty tree | 2 | -- |
| missing argument | 1, before any git work | yes |

It prints pin, main-BEFORE and HEAD-AFTER on every run, so the before/after is
in the log rather than assumed.

### The measured arms (posterior math's measurement, `upfc_out/post_run/g456_arms.rds`)

Read here from the file, not from a note. 49,349 observations:

| arm | 12S | 18S | COI | new species | swaps |
|---|---|---|---|---|---|
| G4 (current main) | 15,015 | 265 | 4,054 | 0 | 0 |
| G5 | 13,962 | 201 | 3,629 | 0 | 0 |
| G6 | 10,528 | 195 | 3,249 | 0 | 0 |
| G5+G6 | 10,469 | 195 | 3,230 | 0 | 0 |

Against the pre-item-b baseline (10,541 / 364 / 3,819), G5+G6 puts 12S back
within half a percent of where it started, 18S 46% below it and COI 15% below.
The cumulative 12S +42% reported on the morning of 10-08 is expected to be given
back almost entirely. That is the guards working, not a regression.

### Measured G6 is a two-pass oracle (my superset argument retracted)

Measured G6 is a **two-pass oracle**. It picks its capped observations using the
G4 *final* consensus rank:

```r
cap <- fin$observation_id[fin$consensus_rank %in% "species" & !lr %in% "species"]
```

run consensus, see which came out species, undo the raises there, re-run
consensus.

**Corrected 2026-10-08, same day**: I first argued a built G6 could not do this
and would therefore block on a strict superset. The coordinator relayed posterior
math's design note: built G6 also runs `posterior_consensus` after raising, over
the observations whose likelihood-only rank is coarser than species, and undoes
raises only where that consensus is species. That selects the same capped set, so
the superset argument does not apply -- it was an argument against a single-pass
build, which is not what is being built.

The risk moved rather than vanished. The build's cap-selection pass now computes
a consensus of its own, while the measurement took its cap from the full G4 run's
final. If that pass runs over the restricted set while the G4 final came from the
whole frame, the two caps can diverge for exactly the reason §7i is open. So the
identity check is the right test, and **if it comes back dirty, look at the cap
before the guard arithmetic**.

### The acceptance test is a per-observation set, not a count

The arms files carry per-observation taxon and rank for every arm, so agreement is
reported as "N of N observations identical in both taxon AND rank", with any
disagreement listed by `observation_id`. Counts are a by-product. Reasons:

- a count match hides compensating differences -- one species call lost and
  another gained nets to zero and reads as agreement;
- a count mismatch of 1 is undiagnosable as a total but names the observation as
  a set;
- NA (no call) is a THIRD outcome and must be scored as itself. The arms disagree
  on which observations get no call at all: on 12S, NA rank is G4 17, G5 23,
  G6 20, G5+G6 26. Letting NA fall into "not species" would score a
  species-to-no-call change the same as species-to-genus.

### The sole-candidate choice is 115 observations, not one

Kevin's pending (a)/(b) choice is measured in two separate files -- (a) in
`g456_arms_soleA.rds`, (b) in `g456_arms.rds` -- with identical `observation_id`
order, so they compare row-wise directly.

The figures were first paired wrongly: 10,527 is **(a)'s G5+G6** and 10,528 is
**(b)'s G6**, two different arms, and the one-observation gap between them is a
coincidence. Like for like:

| arm | 12S | 18S | COI |
|---|---|---|---|
| (a) G5+G6 | 10,527 | 195 | 3,249 |
| (b) G5+G6 | 10,469 | 195 | 3,230 |

They differ on **115 observations** under G5+G6 and **804** under G5-only, and in
every single one **(a)'s call is identical to G4**. So the choice is not a
stringency dial; it decides whether these rows are exempt from both guards.

| marker | differing | species in (a) | species in (b) | (b) drops to NO CALL |
|---|---|---|---|---|
| 12S | 74 | 58 | 0 | 6 |
| 18S | 19 | 0 | 0 | 0 |
| COI | 22 | 19 | 0 | 0 |

115 observations differ but only 77 species calls do -- all 19 of the 18S
differences are order -> class, invisible to a species count. The
per-observation test earned its keep on the first comparison it was applied to.

(b)'s outcomes on those rows: 12S genus 8, family 57, phylum 3, no call 6; 18S
class 19; COI genus 19, family 2, order 1. Two for Kevin's eye. Six 12S
observations lose their call entirely (family Gobiesocidae x5, Clinidae x1 ->
NA). Three fish go family Cottidae -> **phylum Chordata**, which is the queued
fish-class pathology (GBIF `class` is NA for every fish row; the true node is
Actinopteri), so part of (b)'s cost here is that separate bug, not the guard.

Species calls (b) removes and (a) keeps: *Sardinops sagax* 16, *Naineris
dendritica* 15, *Heterostichus rostratus* 11, *Atherinops affinis* 7, *Boccardia
proboscidea* 4, *Engraulis mordax* 3, *Gasterosteus aculeatus* 3, *Medialuna
californiensis* 3, then two each of *Cheilotrema saturnum*, *Menticirrhus
undulatus*, *Rhacochilus toxotes*, *Rimicola muscarum*, *Scorpaenichthys
marmoratus*, and one each of *Anisotremus davidsonii*, *Atractoscion nobilis*,
*Etropus crossotus*, *Hypsypops rubicundus*, *Semicossyphus pulcher* (the
sheephead of the §7f thread).

**The conceptual point.** G5 asks whether the winner beats the best OTHER
referenced candidate by more than the likelihood's own noise. On a sole-candidate
row there is no other candidate -- nothing to beat. Treating "no competitor" as a
*failure* of a separation test inverts it: no competitor is the easiest case, not
the hardest. (a) is therefore not the lenient option with (b) the strict one;
(b) applies a comparison where the comparison does not exist. Recommended to
Kevin (as a recommendation, not a decision): **(a)**.

**Mechanism NOT established.** The hypothesis was that `gap <- L - L2` with
`L2 = -Inf` for a sole candidate gives `gap = Inf`, which fails the
`is.finite(gap)` term in

```r
g5_block <- raised & ref & !(is.finite(gap) & gap > Z * band)
```

so a maximally clear win blocks. This did NOT hold in `g5_moves.rds`: 0 infinite
gaps, 0 NA `runner_up`, 0 NA `sd_w`. But that table covers only the 3,334
genus->species moves, not the sole-candidate rows, so it neither confirms nor
refutes it. Posterior math should name the mechanism from its own code rather
than inherit this guess; the question is what the comparison evaluates to when
there is no second candidate.

### HOLD 2026-10-08: general methods, or patches for this dataset?

Kevin paused the whole G5/G6 line to review exactly this. Nothing is to be
merged or installed until the coordinator relays his decision; posterior math is
not handing off a SHA meanwhile. The per-observation acceptance method above
stands for whatever eventually gets built.

The question is partly testable from the measurements already on disk. Under
Kevin's standing rule -- no hard-coded rules for particular markers, decisions
learned from the data -- a marker-uniform effect looks general and a
marker-dependent one looks like a patch. Removal as a fraction of that marker's
G4 species calls:

| marker | G4 species | G5 | G6 | G5+G6 |
|---|---|---|---|---|
| 12S | 15,015 | 7.0% | 29.9% | 30.3% |
| 18S | 265 | 24.2% | 26.4% | 26.4% |
| COI | 4,054 | 10.5% | 19.9% | 20.3% |

G6 is near-uniform (1.5x spread). G5 is not (3.5x), which first looked like the
patch signature. **It is not.** Decomposing `z = gap / band`, where
`band = sqrt(sd_w^2 + sd_2^2)`, medians by marker:

| | 12S | 18S | COI |
|---|---|---|---|
| band | 0.059 | 0.060 | 0.067 |
| gap | 0.553 | 0.398 | 0.242 |
| z | 9.07 | 4.49 | 3.67 |

The band -- the part the rule constructs -- is already **marker-invariant**,
which is what `calibrate_query_noise()` is meant to deliver and is consistent
with the 2026-09-30 finding that the score scale is constant across markers. All
the marker dependence lives in the **gap**: 12S references separate congeners
about twice as well as COI's do. That is biology and reference coverage, not a
property of the rule.

So one fixed Z giving different block rates per marker is the *correct*
behaviour. The decisive check: equalising the block rate across markers would
need Z = 3.86 (12S), 0.67 (18S), 1.60 (COI) at a 30% target -- a per-marker
constant, precisely what is forbidden. **Here a uniform effect would be the
patch; the uneven effect is the data speaking.**

Where G5 is still patch-shaped is NOT the marker question: `Z = 1.96` is the
two-sided normal 95% quantile, a value from a table rather than learned from
these data. That is the part that fails "learned from the data" -- not that Z is
shared across markers (it should be) but that its value was chosen by
convention. A learned version fits Z once, across all markers, against the
error-side evidence Kevin optimises.

G4 and G6 carry no constant at all and are structural, zero-parameter
invariants: maximally general in form. But G6 denies the prior any power to
*improve* rank resolution, allowing it only to confirm or degrade. Defensible --
priors inform confidence, not rank -- but a methodological commitment to argue
in the manuscript, and the one a reviewer is most likely to challenge.

**Caveat that undercuts every 18S figure above.** The z analysis rests on the
genus->species moves, and 18S has only SEVEN. Its 42.9% block rate is 3 of 7:

| marker | n | rate | 95% CI |
|---|---|---|---|
| 12S | 3,125 | 0.123 | [0.112, 0.135] |
| 18S | 7 | 0.429 | [0.099, 0.816] |
| COI | 202 | 0.386 | [0.319, 0.457] |

The 18S interval spans 0.10-0.82 and overlaps both other markers, so no
18S-specific conclusion about G5 is supportable from this run. 12S and COI do
separate.

**And the limit on all of it:** every figure comes from one dataset. A rule can
have general form and still be a patch in effect if it was only ever tuned and
checked on the dataset it was written for. Form is testable from here;
generality in effect needs a second dataset (PtConception or GreatLakes), which
is a run and therefore Kevin's call, not something this session starts.


### The decisive split

1. **On the capped set**: built and measured perform the identical operation --
   restore the Round 1 prior on every raised row -- so they must agree
   **exactly**. Disagreement is a real finding: an implementation difference, or
   cap divergence from frame dependence (§7i). HOLD on this.
2. **On the complement**: whatever the build does is new information, not a
   mismatch. Report species added, species removed and coarse calls changed as
   its own figure; do not score it against the arms and do not hold the run for
   it. Holding because an unmeasured set behaved unlike a set it was never
   measured on would be holding for the wrong reason.

G5 carries a milder version: the measurement joined `score_likelihood_sd` from
`CalIntertidal_lik.rds` through a two-try observation-id match (`j`, then `j2` on
a stripped prefix) and printed an unmatched count; the build has `sd` natively.
`g5_moves.rds` shows 0 NA `sd_w` among the moves, so the join was complete there.

Memory: the arms files are ~570 KB each and every comparison object is under
250 KB, so the capped-set check sits well inside the 3 GB the coordinator set.
Re-running the built consensus over the full frame is the workflow's job, not
this session's.


### Winner, the API resolution, and the public-surface check (2026-10-08)

**Winner: G5+G6 under sole-candidate option (a).** The two alternatives failed
on the measurements added at this session's request: the graded-donor arm (Rg+G6)
produced 29 new species calls (T1), and the ungated resolved-only arm (R+G6)
produced a 30-call donor cliff (T3) -- the GreatLakes-shaped failure the cliff
check was added to catch. Details in posterior math's `rs_report.txt`. So the
graded arm this session proposed was measured and lost, which is the right
outcome for having measured it.

**The build adds no public surface**, after the API problem was raised and the
coordinator routed it: `z` becomes the internal constant
`.ROUND2_LIKELIHOOD_MARGIN_Z`, and the consensus settings travel as an internal
attribute on `posterior_consensus()` output, read by
`update_prior_from_consensus()` with an abort if the attribute is missing.

#### An exports diff cannot see a new argument

`58d9944` added `likelihood_margin_z = 1.96` and `consensus_args = NULL` to the
already-exported `update_prior_from_consensus()`. That is new public API, but it
changes no NAMESPACE line, so `git diff -- '*/NAMESPACE' | grep '^[+-]export'`
reported **none** and the release freeze would have been bypassed. NAMESPACE is a
proxy for public surface, not the thing itself.

`verify_merge.sh` now compares the **formals of every exported function**: read
each package's `export()` lines, locate each name's top-level definition in `R/`,
emit a canonical `Pkg::fn(arg = default, ...)` line, and diff that list between
the BEFORE tree (`git archive`) and the merged tree. Tested against `58d9944`,
where the answer was known in advance, it reports exactly one changed line out of
**230 exported signatures** and nothing else. It also diffs NAMESPACE as a whole,
not only `export` lines, so an S3 registration or import change cannot pass
either.

Anti-vacuity: abort if the scan emits nothing, exit 8 if either side yields fewer
than 100 signatures, exit 7 if the scan itself fails. Audited for silent gaps --
no parse errors across the nine packages, and the five exports reported as having
no function definition are genuine data objects (`standard_ranks`,
`extended_ranks`, `barcode_length_defaults`, `barcode_primer_defaults`,
`example_habitat_scheme`), stable across before/after and acting as sentinels.

R trap found while implementing it: never bind a formal's default to a variable,
because assigning the empty symbol makes that variable *missing* and the next
reference errors with `argument "d" is missing, with no default`. Deparse inline.

#### State of 58d9944 for reference

The full cycle ran clean on it: no conflicts, inventory matching the tree,
TaxaAssign 1189 passed / 0 failed / 0 errors / 1 skip, CI-equivalent rcmdcheck
0 errors / 1 warning (pre-existing) / 0 notes. What stood between it and a merge
was the API change and the missing review-response entry, not the code.

#### Acceptance settings for the handoff

Reference `g456_arms_soleA.rds`, columns `t56` / `r56`; capped `observation_id`
list arrives with the SHA. Exact per-observation agreement required on the capped
set (`compare_arms.R`, exit 9 on any disagreement); the complement reported
separately and not scored. Install only once **every** R-family process has
exited, not just the two named. Then CalIntertidalWorkflow gets its GO. SHA due
~10:15 (build started 08:20).


### MERGED AND INSTALLED: round2-g56 at dee0bdc (2026-10-08 08:19-08:26)

| | |
|---|---|
| main | `b0ee48c` (merge of `dee0bdc`), then `f6b16f0` for the pack |
| TaxaAssign installed | `2026-10-08 15:22:15 UTC` |
| tree | `5a25450995e49e73b59b6578383ab144788288ae` -- identical to the tree rcmdcheck passed |

Verification of the MERGE: pin exists, was not already an ancestor, HEAD moved,
10 files changed; exports diff none; NAMESPACE unchanged; **exported formals
UNCHANGED across all 230**; inventory recomputed from the tree matches;
TaxaAssign 1197/0/0/1 (was 1161); rcmdcheck 0 errors, 1 pre-existing warning,
0 notes; TaxaWizard 1154/1 before the pack regen (`test-pack.R`) and 1155/0
after. Installed-package behaviour confirmed, not just the build stamp:
`.ROUND2_LIKELIHOOD_MARGIN_Z` = 1.96 present, guard code in the body, and the
exported formals are the ten pre-existing ones.

**Acceptance, exact.** Matching both taxon and rank with no-call as its own
outcome: 4,586 of 4,586 on the capped set, and 49,349 of 49,349 over the full
frame. Species calls G4 -> built: 12S 15,015 -> 10,527, 18S 265 -> 195, COI
4,054 -> 3,249.

**The honest figure is 5,612, not 49,349** (corrected same day). `g56_identity.R`
seeds `t_built`/`r_built` from the G4 columns at line 98 and overwrites only the
observations it recomputed at line 100, so every row it did not recompute carries
the G4 value on both sides and agrees *by construction*. The substantive count is
the changed rows:

| | changed vs the G4 seed | of |
|---|---|---|
| capped set | **4,586** | 4,586 |
| complement | 1,026 | 44,763 |
| total | **5,612** | 49,349 |

All 5,612 matched the measured arm. Every capped observation changed, so the
capped-set result has no trivially-agreeing rows in it -- the acceptance test was
100% informative on the set it was designed around, and the full-frame number
simply includes 43,737 rows that could not have disagreed.

**Provenance of `t_built`, checked in the source rather than taken on
description.** `g56_identity.R` line 100 writes it from a real
`posterior_consensus()` run over the affected observations; `t56` is read only in
the comparison at line 101. So it is not a copied column, and the limit recorded
here earlier is closed. The production run is the full-frame test.

#### QUEUED FOR KEVIN: the pack silently omits behaviour that can abort a run

`posterior_consensus()` now attaches a `consensus_settings` attribute and
`update_prior_from_consensus()` **aborts without it**. Row subsetting keeps it;
`merge()`, `dplyr::summarise()` or rebuilding the data frame **drop** it.

Both facts are in the installed Rd. Neither is in `llm_prompts`: the generator
truncates Value text and the attribute paragraph falls past the cut, so
`consensus_settings` appears **nowhere in the pack**. A consumer working from the
pack -- which the pack itself instructs readers to "trust over any prior
knowledge of TaxaID" -- cannot learn that the attribute exists or that ordinary
dplyr operations silently remove it. The regeneration's only real content change
was `require_support_columns`' description.

A generator limitation, not a defect in the merged code, and it did not block the
merge. But it is the pack asserting completeness it does not have, so it belongs
with the items for the maintainer.

## 7m. Threshold audit of the whole guard line (2026-10-08)

Kevin's pause asks of each item whether it generalises or is a patch to reach a
desired outcome, and specifically whether its threshold is learned or
conventional. That audit is mechanical: diff each merge for numeric parameters
added to `R/` code. **The review covers work already merged AND installed**, so
it must be read against main, not against a list of proposals.

### State of main (TaxaAssign build 2026-10-08 05:02:54 UTC)

> **Point-in-time, superseded for CURRENT state by §7o.** The table below
> predates the G5+G6 merge: it lists G5/G6 as unmerged and names an earlier
> build. It is still the correct record of what the threshold audit examined.

| SHA | item | behaviour |
|---|---|---|
| `8cc0c36` | upfc-memory | none (memory only) |
| `4acf4d3` | b | soft confirmation excludes unreferenced relatives |
| `46cea96` | pc-index-split | none (memory only) |
| `2b03be9` | a | `restore_suppressed_candidates`, measured-first |
| `9b3f21a` | C1 | query-noise calibration from observed rows only |
| `c0e8eac` | G1 + G3 | occurrence record (G1), likelihood-only credible node (G3) |
| `58c625a` | G4 | likelihood ranking |

Not merged: k (cross-phylum, frozen `6cd806d`, post-run only), G5, G6.

### New numeric parameters per item

| item | new numeric parameters in `R/` |
|---|---|
| b | **zero** |
| C1 | **zero** |
| G1 + G3 | **zero** |
| G4 | **zero** |
| a | **four**: `min_query_coverage = 0.8`, `max_obs = 3000L`, `min_obs = 30L`, `max_per_obs = 10L` |

So the five behavioural changes most likely to attract the patch worry -- b, C1
and the three guards -- are **parameter-free structural invariants**. There is no
threshold in them to tune to an outcome. The guards read in code as principles
with one measured example each:

- **G1** a row with no occurrence record (`theta_mean` `NA`) is never raised
- **G3** a raise stays inside the observation's likelihood-only credible node
- **G4** a prior boost must not overturn the likelihood ordering (ties allowed)

under one sentence: *"A raise may choose among candidates the sequence cannot
separate; it may never pick one the sequence argues against, nor manufacture
presence."* That is the general-principle-first form the review asks for.

### The real exposure is item (a), already merged

Item (a) is the only item in the line carrying conventional constants, and two
independent problems with its calibration were flagged before this review: the
offset is estimated from each observation's **best** hit but applied to **low**
scores, and it is **discontinuous at `min_obs = 30`**. `min_query_coverage = 0.8`
is also the parameter whose public status is unresolved -- indirect approval only,
with an internal alternative at `b6959d5`. If one item is to be re-examined for
"threshold learned or conventional", it is (a), not the guards.

G5 would add `Z = 1.96`, the first tuned constant in the guard line proper and
conventional rather than learned. G6 adds none.

### Revert path, recorded not proposed

Kevin's note that he agreed to some of this "because I have been tired and felt
the need to move on" applies to decisions that reached this session only as
relayed quotes -- "go ahead and implement C1 + G3, and G1", "YES" to the breaking
`require_support_columns` default, "OK. let's do G4." Each was recorded with its
relay provenance rather than as direct approval, and each is a clean single
merge, so the path back is short. Nothing here proposes a revert; the point is
that "already merged" must not become the reason to keep something he would not
choose again.


## 7n. Resolved-only support: measured, not built (2026-10-08)

Kevin, relayed verbatim: *"yes, measure resolved-only support first"*. Under it a
site prior borrows only from observations whose likelihood-only call resolves the
taxon. Measurement only; nothing to merge.

**Label provenance (corrected 2026-10-08).** The G-numbers come from the
decision thread, not the code -- the roxygen names the three guards without
numbering them -- so the coordinator is the authority on the mapping. It is
**G1 = occurrence record, G3 = likelihood-only credible node**; an earlier
version of this section and of §7m had the two swapped. The substance is
unaffected: the receiver guard that pairs with resolved-only support is the
node one, G3.

### What the donor side does today

Support is `max(posterior_point_est)` per (observation, species), summed over
group members, discounted by `confirmation_discount` (a0 = 0.25). Donor
eligibility is only `!is.na(taxon_name) & !is.na(posterior) & is_ref`, where
`is_ref` is item b's exclusion of unreferenced types. So every observation
contributes support for a species in proportion to its posterior support for it,
whether or not its own sequence evidence picked that species out -- as the code
states: the soft version "aggregates EVERY observation's posterior support for a
species as fractional evidence of site-level presence."

### Why this is a root-cause fix rather than another patch

Donor mass is built from the POSTERIOR, and the posterior already contains the
prior, so the circularity is structural rather than hypothetical. The package
already makes exactly this argument one level down, at item b: ring rows'
"posterior support comes from the same rows across the Site, so letting them
confirm each other is circular (CalIntertidal 2026-10-06: ring priors rose
3.5e-6 -> 0.049)." Resolved-only support applies the same argument to
observations: one that could not resolve the taxon on its own sequence evidence
is substantially expressing the prior, so letting it confirm the taxon feeds the
prior back into itself. It is the principled completion of an argument already in
the code -- the strongest general-method credential anything in this line has.

It is also the **donor-side twin of G3**: G3 gates the receiver on
`likelihood_consensus_taxon` / `likelihood_consensus_rank`, and this gates the
donor on the same columns. One principle covers both -- *mass flows only between
observations whose own sequence evidence identifies the taxon* -- which is a
better methods story than three receiver guards plus a separate donor rule.

Two precisions so it is not oversold:

- The two sides are **not the same test**. G3 asks whether the receiver row is
  CONTAINED in its observation's likelihood node, which may sit at class rank
  (permissive). Resolved-only asks whether the donor's node IS the taxon
  (strict). The asymmetry is defensible -- a donor asserts presence, a receiver
  only chooses among candidates the sequence cannot separate -- but it should be
  a stated choice, not an accident.
- It **does not subsume G4 or G1**. G4's invariant is about ordering inside the
  receiving observation; restricting donors reduces available MASS but cannot
  restore an ordering, so with enough resolved donors a raise can still overturn
  the likelihood ordering. G1 concerns a receiver row with no occurrence record
  at all. Resolved-only makes G4 bind less often, not unnecessary. It composes
  with b rather than replacing it: b filters row TYPE, this filters observation
  RESOLUTION.

### The risk the measurement must be built to catch

The soft design exists because the hard version failed. From the code: gating
donors on "resolved it with `consensus_posterior` >= a threshold" is
classification EM (Celeux & Govaert 1992) and "would produce real cliffs: one
marginal competitor holding every observation just under the bar means ZERO
donors dataset-wide -- the GreatLakes2023 yellow-perch case, 78 observations at
~0.69 each, no confirmation anywhere."

Resolved-only support reintroduces a **binary donor gate**. The gated quantity
differs (likelihood-only resolution, not a posterior threshold) so it is not the
same cliff, but it is the same SHAPE, and GreatLakes2023 is the dataset known to
expose it. The measurement should therefore report the **donor-count
distribution** -- how many (group, species) cells lose all donors, and
before/after donor counts per cell -- not only the resulting species calls, and
should check GreatLakes2023 yellow perch specifically. On CalIntertidal alone a
zero-donor cliff can be invisible.

### A graded version the package already computes

`posterior_consensus()`'s likelihood-only pass already emits
**`likelihood_support`**: the "share of the baseline (sequence evidence, named
candidates' priors flattened) that falls in the reported taxon", computed as
`sum(.lik_post[taxon matches]) / sum(.lik_post)`. That is the *continuous*
version of exactly the quantity resolved-only support would threshold.

Weighting donor mass by it -- or building donor mass from the sequence-only
`.lik_post` rather than the prior-containing posterior -- achieves the same goal
with no binary gate, no cliff and no new parameter. For the general-vs-patch
question that is the stronger form: it **removes** a threshold instead of adding
one, so there is nothing to be accused of tuning. If resolved-only is measured
binary-first, the graded variant is a cheap second arm on the same frame and
worth having before a method is chosen.


## 7o. STATE AT SESSION END (2026-10-08, verified not recalled)

Written before a `/clear` of the package-review session. Every fact below was
re-checked against the repository, the library and the run artifacts at the time
of writing, not carried from conversation.

### Current state

| what | value |
|---|---|
| main tip | `9c17243` (board only; last **code** merge `b0ee48c`, pack regen `f6b16f0`) |
| worktree | `/Users/lafferty/taxaid-worktrees/main`, clean |
| TaxaAssign installed | build **2026-10-08 15:22:15 UTC**, `~/Library/R/4.0/library` |
| R-family processes | none; the CalIntertidal production run has finished |
| install gate | open (coordinator lifted run restrictions; normal <=3 GB rule) |
| not merged | **k** (`cross-phylum`, frozen `6cd806d`, post-run only) |

This supersedes the table under §7m "State of main (TaxaAssign build 2026-10-08
05:02:54 UTC)", which was point-in-time and still lists G5/G6 as unmerged. Read
§7m as the dated threshold audit it is, not as current state.

### The production run's post-run checks -- VERIFIED from the artifacts

G5 violations 0, G6 violations 0, `identity_final_vs_built_g56.rds` 0 rows, k
applied. Species calls 12S 10,527 / 18S 195 /
COI 3,249, exactly as the measured arm predicted.

Two traps for whoever reads these artifacts next:

- **G6's violation test is `raised & sp_no_lik_sp`** (`post_run_checks_g56.R:79`).
  The raw `sp_no_lik_sp` column is **2,070** and is *not* the violation count --
  G6 constrains Round 2 raises only. Do not quote the column.
- **There are two different 49,349 identity tests.** `g56_identity.R` seeded
  *both* sides from G4, so its honest figure is 5,612 changed rows.
  `post_run_checks_g56.R:169-181` computes the left side from the production
  run itself and seeds only `t_built`/`r_built`, so **its** 49,349/49,349 is a
  legitimate no-side-effects result. Never restate one as the other; an 08:20
  email did and was corrected.

### Residual errors improved under both definitions

| definition | G4 run | G5+G6 run |
|---|---|---|
| strict, winner below runner-up by >1 pt | 105 (12S 87 / 18S 1 / COI 17) | **57** (12S 52 / 18S 0 / COI 5) |
| script, winner <= runner-up or <90 | 1,605 (8.30%) | **647** (4.63%) |

The G4 side reproduces the figure recorded in memory exactly, so the artifact
and both definitions check out.

### NEW FINDING: 73% of the surviving error is outside what G5/G6 can reach

Cross-tabbing `residual_errors_g56.rds` against `g6_invariant_g56.rds`:
**474 of the 647** survivors are *unraised* species calls whose likelihood-only
consensus is not species -- Round 1's prior turning a genus-level likelihood
into a confident species call. Only **11** were raised by Round 2. Residual rate
**22.9%** in that class (2,070 calls, 14.8% of confident species calls) against
**1.5%** in the 11,901 likelihood-backed calls.

These are **not** guard violations. G5/G6 constrain Round 2 raises by
construction, so the failure mode lives in Round 1 and the guard family cannot
see it.

`likelihood_support` already grades the same thing continuously
(`posterior_consensus.R:1099-1108`), with no per-marker constant. Residual rate
by band: 0-0.2 **64.8%** | 0.2-0.4 **54.4%** | 0.4-0.6 **27.8%** |
0.6-0.8 **6.1%** | 0.8-0.95 **6.7%** | 0.95-1 **1.2%**
(n = 88 / 364 / 562 / 737 / 887 / 11,333).

**Do not over-read this.** The *direction* holds in all three markers; the
*slope* does not. 12S is steep and clean (90% -> 0%). COI is shallow and
non-monotone (0.6-0.8 at 29% sits *above* 0.4-0.6 at 21%) and still carries 122
residual errors inside the top band, so support alone does not explain COI. 18S
has 2 errors total and settles nothing. A single global cut on this column would
behave differently per marker. Reported to Kevin as a **diagnostic and candidate
weight, not a proposed threshold**; a Round-1 prior refinement is a new design
question for him, not a fix inside an existing function, so it does not pass the
release freeze on its own. Scripts are session-scoped scratchpad copies
(`overlap.R`, `liksupp.R`, `resid_defs.R`) -- regenerate from the two artifacts
rather than hunting for them.

### Open items, with where each already lives

1. **`llm_prompts` omits `consensus_settings`** -- §7l, "QUEUED FOR KEVIN".
   Generator truncates Value text; `update_prior_from_consensus()` aborts without
   the attribute and `merge()`/`summarise()` drop it. Generator limitation, not a
   code defect. Needs the maintainer.
2. **Item (a)'s constants and calibration** -- §7m, "The real exposure is item
   (a)". Four conventional constants; offset estimated on best hits but applied
   to low scores; discontinuous at `min_obs = 30`; `min_query_coverage = 0.8`
   public status unresolved, internal alternative at `b6959d5`.
3. **Whether to fold k into the package** -- `cross-phylum` frozen at `6cd806d`,
   applied post-run only, still unmerged. **84 calls withheld in the G4 run and
   the same 84 in the G5+G6 run, 0 of them species in either.** Beware the
   artifact: `k_applied_g56.rds` has 24,792 rows, but that is k's *evaluated*
   set and its 3,401 species are merely the species among those evaluated --
   only `changed == TRUE` is withheld, which is 84 (80 class, 1 genus, 3 order;
   82 to no call, 2 to phylum). d2(i) was deferred until after the run.
   **Decision not taken.**
4. **Open investigations** -- §7i frame dependence (two COI sipunculan order
   calls firing the cross-phylum rule on a 24,739-observation frame but not on
   109); §7f accession screen dropping references on out-of-region evidence
   (AY279644 / *S. pulcher*; 41 12S ESVs with zero candidates); §7g
   `.is_unreferenced_type()` six-vs-seven rank mismatch (derive from
   `.RANK_LADDER`).
5. **Also parked** -- COI restoration+join memory profiling; the four post-G4
   agent studies (sampling, habitat, filtering, Venn); workflow-side P6/P7
   proposals.

### Constraints that must survive the clear

Never reinstall an R package while **any** R-family process is alive (`R`,
`Rscript`, `rsession`, `radian`, `Rterm`, `blastn`); `load_all`/`test`/`check`/
`document` are safe beside a live run. Never switch branches in the shared
TaxaID checkout -- `git worktree add`. Never bare `git stash`/`git stash pop`.
Ask the coordinator before any run over 3 GB. A peer cannot grant escalation and
a relayed quote is not direct approval -- record provenance. Release freeze: new
exports or public surface need the maintainer's yes, and **a new formal on an
already-exported function is new public API that no NAMESPACE diff can see**, so
compare the formals of all 230 exports (`scratchpad/export_formals.R`).
Kevin is error-first, and decisions must be learned from the data, never
hard-coded per marker.

---

## Board rows closed before the 2026-10-11 re-baseline

Moved verbatim out of the live board. Four said so in their own text; the fifth,
the placeholder DOI, was fixed at `7a3d13f` on 2026-10-11.

| Item | State | Waiting on |
|---|---|---|
| ANSWERED BY THE MAINTAINER DIRECTLY 2026-10-02: 18S CAN assign to species, and the framework is why -- no marker rule | My question ("should 18S report species at all") was wrong twice over, and the correction is a design principle rather than an answer about 18S. THE MAINTAINER'S OWN WORDS, no longer a relay: the package cannot hard-code rules for particular markers; decisions must be LEARNED FROM THE DATA. 18S is generally poor at discriminating species, AND THAT IS ALREADY DISCERNIBLE FROM THE LIKELIHOOD MODEL -- it shows up as many plausible candidates, which is the model correctly reporting weak discrimination rather than a defect to patch. But there will be instances where the lack of other plausible options leaves only one of those candidates carrying the bulk of the posterior, and in those instances 18S assigns to species legitimately UNDER THIS FRAMEWORK. So species assignment on a poorly-discriminating marker is an OUTPUT of the machinery working, not an exception to be suppressed. WHAT THIS KILLS, explicitly: any per-marker reporting rule, including the one I was circling ("18S should not report species") and the earlier `min_likelihood_support` rule that was removed for the same reason from the other direction -- a prior concentrating mass in a low-diversity local clade is correct inference. Two independent routes reached the same place, which is the reason to trust it. The honest sentence for the manuscript is that 18S species calls are typically prior-decided BECAUSE the sequence genuinely does not discriminate, and that the framework reports both parts (`likelihood_support` for what the sequence did, the posterior for what the evidence plus the prior concluded) rather than choosing for the reader. WHAT REMAINS MEASURABLE, and is NOT a reporting question: how often the prior is wrong, i.e. a local relative present but unrecorded -- answered by the counterfactual test (scenarios F3 and D-a) and addressed through the per-clade prior for unrecorded relatives, which is exactly where the dark-diversity budget rebuild now merged on main does its work | nothing: closed |
| CLOSED: the Step 5 slice, its object split, and the shared predicate, all verified | Three rounds, all resolved. (1) The species slice became its OWN object, `occurrences_kernel`, so `occurrences_clean` stays the full pool and the three downstream readers see exactly what they saw before. (2) I verified the split in three parts: COMPLETE, no theta-path use still reaches the full pool; CORRECT, `RANK_LADDER` is `c("species","genus","family")` so the expression yields exactly "species", checked against the ladder rather than inferred from the row count, because a coarse-first ladder would have made the slice a NO-OP that the arithmetic could not distinguish; CONSISTENT, 932,752 minus 848,757 is 83,995 against the roughly 84,000 coarse records. (3) The duplicated predicate is now ONE rule: `rank_or_finer(df, rank)` in `pool_access.R`, called by both `pool_at_rank()` and the workflow. Verified: the helper validates its own rank with `match.arg`, so the new public entry point does not bypass the validation living at the old one, which would have been the exemption-list shape again; `pool_at_rank()`'s body holds no copy; the workflow's explicit assign allow-list actually includes the helper, which was the real failure mode since the helper could have been defined and still invisible; and only one definition exists anywhere, so nothing shadows it and the change is additive for the five PtConception scripts that source the file. A SUGGESTION OF MINE WITHDRAWN AFTER CHECKING: calling `pool_at_rank("species")` on the hand-filtered table would not work, since it re-reads the pool from a path, so the original inline copy was necessary and a workflow comment had been asking for something the signature does not offer. The regression check's expected value of ONE is written beside the check in Step 7 | -- |
| Group merge (LANDED `82d3bd0`; superseded row kept for the record) | Merging `flag-failed-libraries` (`ab41741`) then `sample-identity-gate` (`0b409b4`) into main costs two small text conflicts, both in the first (TaxaFlag/CLAUDE.md and the review-response table, where `flag_hopped_detections` already landed); the second merges clean. TaxaFlag would go 12 to 15 exports and 14 to 17 test files, so the root README's Software Inventory row and TaxaFlag's own function list both need the three new names before the merge is to standard. Two handoff documents on those branches move to TaxaID_dev. The LLM branch is VERIFIED at `4d9a097`: 854/0, check 0/0/0, a real tutorial run (374 observations, every prior from the LLM, no fallbacks), and it carries two bug fixes of its own, the per-batch prior normalisation and an omitted taxon receiving prior 0 (silently eliminated with `prior_phi = NULL`, aborting the run otherwise) | the maintainer: the group's go, once the LLM branch is verified and the README round is done |
| Branches awaiting the maintainer's yes (LANDED; superseded row kept for the record) | `flag-failed-libraries` (`ab41741`, now also single-marker run failure and a `failure_basis` column, 672/0), `sample-identity-gate` (`0b409b4`, rebased onto it, 771/0) and `llm-pathway-audit` (`0e639e9`), plus the maintainer's in-progress root README round in the shared checkout. The LLM branch carries a real bug fix (LLM priors were normalised per batch, so a lone implausible taxon in a small final batch could win at posterior 0.495) and one behaviour change consistent with the A3 precedent (`run_llm_pipeline(data_type =)` with no default). The maintainer's decision 2026-09-28: these move forward AS A GROUP, not piecemeal. The two TaxaFlag branches edit the same four files, so they merge in one sitting, oldest first, and this session resolves | maintainer |
| Placeholder DOI in all ten READMEs | `https://doi.org/10.5066/xxxxxx` appears in the root README and all nine package READMEs, and the URL check reports it. It is the USGS release DOI, assigned at release, so the placeholder is correct for now and MUST be filled before publication. Noticed because the CI-equivalent check reports it; CI itself passes, since it fails only on errors | submission |

**Resolution of the last row, 2026-10-11.** The maintainer settled the framing:
TaxaID is public but not a citable object, and the citable object will be the
USGS release. The placeholder was therefore replaced, in 12 places rather than
the 10 this row counted -- the root README carries it twice and
`TaxaWizard/R/shiny.R:1327` wrote it into the citation text the generated app
hands the user -- with a statement that the software is provisional and not yet
citable, plus the repository URL (`7a3d13f`). The USGS software-release framing
is kept for the eventual official release.
