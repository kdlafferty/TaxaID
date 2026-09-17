# Workflow drift checks

Two checks that catch the class of defect the 2026-09-15 production workflow
structural audit missed. Run BOTH against ALL live workflow files after any
workflow edit, not just the file you touched -- the whole failure mode here is a
broadcast fix reaching some files and not others.

| Script | Finds |
|---|---|
| `check_dead_calls.sh` | Calls to functions that were ARCHIVED out of a package (`Taxa*/archive_*/`) and never re-exported. Catches bare calls, which a namespace sweep does not. |
| `check_stale_arguments.R` | Named arguments that no longer exist in the installed function's formals. Catches a signature change that a structural read cannot see. |
| `test_subset_helper.R` | Exercises the template's SUBSET/REUSE block against a synthetic long-tailed fixture: no-op when off, sentinel taxa guaranteed, widest candidate sets retained, reproducible across calls, **global RNG stream preserved**, and stamping present on a subset checkpoint and absent on a full one. It found the RNG leak described below. |

```bash
# from the TaxaID repository root
E="$HOME/My Drive/Rscripts/eDNA"; G="$HOME/My Drive/Stats and Data/GreatLakes data"
FILES=(
  "$E/PtConception/TaxaID_eDNA_Workflow_Template.R"
  "$E/PtConception/PtConceptionWorkflow_12S_single_site.R"
  "$E/PtConception/PtConceptionWorkflow_18S_2_single_site.R"
  "$E/PtConception/PtConceptionWorkflow_12S_multi_site_FAST.R"
  "$E/SepulvedaMugu/MuguFishWorkflow.R"
  "$E/CaliforniaIntertidal/CaliforniaIntertidalWorkflow_multi_marker.R"
  "$G/GreatLakes2023_ConsensusWorkflow.R"
)
bash diagnostics/workflow_checks/check_dead_calls.sh "${FILES[@]}"
Rscript diagnostics/workflow_checks/check_stale_arguments.R "${FILES[@]}"
```

## Reading the output

A dead call is NOT automatically a bug. In the production scripts every one of
them sits inside the `else` of a hardcoded `USE_KERNEL_PRIORS <- TRUE`, behind an
explicit ARCHIVED PATHWAY NOTICE -- documented dead code, deliberately retained
until the GLMM path is formally dropped. Check whether the call is reachable
before touching it (`[[feedback_verify_purpose_before_flagging]]`).

A stale argument is always a hard error, because R matches named arguments
strictly. There is no benign case.

Baseline, 2026-09-17: all six production workflows clean on both checks; the
canonical template clean on both after `5b91fa4`, `d77bc65` and `7e92325`.

## The subset/reuse convention

The canonical template's Section 0 carries a SUBSET/REUSE block built on two
rules. `test_subset_helper.R` checks the mechanism; the rules are what keep it
honest.

**Rule 1 -- a test run writes to its own prefix and only ever reads the other.**
`OUT_PREFIX` is the write namespace, `REUSE_PREFIX` the read-only one, accessed
through `.reuse_path()`. This is a rule rather than a habit because re-saving a
shared upstream object bumps its mtime, and the staleness gates key on mtime --
one such re-save silently invalidated a downstream chain and cost a 2h47m
recompute. Package `cache_dir` caches are the deliberate exception: they are
content-keyed, so sharing one between a subset and a full run is a pure win.

**Rule 2 -- a subset run exercises code paths, never produces numbers.** The
Good-Turing budget (quadratic in `f1`), the LOBO bandwidth, Empirical-Bayes
`tau2`, `calibrate_query_noise()`'s confident-species floor,
`compute_group_priors()`'s compositional `theta_sum` and `flag_contaminant()`'s
read-count shrinkage are all whole-pool quantities and are wrong on a subset,
quietly. Reuse them from a full run via `REUSE_PREFIX` instead of recomputing.

The dangerous case is a NEGATIVE result: a subset that raises no warning looks
like evidence of no problem. That has already happened on this project -- a
bimodality diagnostic's "no flag" on a fast fixture was read as a negative
control and was not one, because the fixture was too small to build a comb
dense enough to win on BIC. Subset status is therefore STAMPED into every
checkpoint (`attr(x, "taxaid_subset")`), into the exported CSV (`subset_run`)
and into `session_metadata.rds` along with the reused checkpoints' mtimes -- a
console line does not survive to whoever opens the file three weeks later.

The subset is applied at ONE point, entering Step 8, because everything
upstream is a whole-pool quantity and everything downstream is per-observation
(and is where the time goes). The strata are data-type neutral -- they key on
`observation_id` and candidate-set width, so they work unchanged for sequences,
acoustic detection windows or image detections.

A real bug this test caught, worth knowing about if you write a similar helper:
a bare `set.seed()` inside the subsetter reseeds the whole session, so
`compute_posterior()`'s Monte Carlo draws would differ between a subset run and
a full run for a reason unrelated to subsetting -- destroying the very
comparison the mechanism exists to support. The helper now seeds locally and
restores `.Random.seed`.

### First real exercise, 2026-09-17 (PtConception 12S)

Run against the completed `PtConMifishSchulte_*` checkpoints (2026-09-14/15),
with those files SYMLINKED into a scratch `OUT_DIR` so that any write violating
Rule 1 would go through to the real file and show up in its mtime.

| | full run | subset |
|---|---:|---:|
| observations | 13,440 | 365 (2.7%) |
| `$likelihoods` rows | 63,703 | 4,281 (15x less) |
| candidates/observation, median / max | 4 / 79 | 4 / 79 |

- **Rule 1 held**: not one reuse-prefix mtime changed, and `.reuse_path()`
  appears only inside `readRDS()`. Nothing was written into the project
  directory.
- Every one of the 175 `Girella nigricans` observations was retained, and all
  40 of the widest candidate sets. Max candidates is unchanged at 79, so the
  hard cases -- the ones that exercise consensus, irreducibility and slash
  naming -- survive the cut rather than being sampled away.

**Two bugs this exercise found, both in the block itself, neither visible on
review:**

1. `lik_result` is `list(likelihoods=, unresolved=)`, not a data frame. The
   first version asserted `obs_col %in% names(x)` and died at the single line
   that matters. The helper is now polymorphic and cuts every frame in a list to
   ONE observation set, so the frames cannot diverge. Pinned by two regression
   tests.
2. A bare `set.seed()` reseeded the whole session, so `compute_posterior()`'s
   1,000 Monte Carlo draws would have differed between subset and full runs for
   a reason unrelated to subsetting. Now seeded locally with `.Random.seed`
   restored.

**Tuning note.** With `SUBSET_ALWAYS_TAXA = SENTINEL_TAXA`, the sentinel took
175 of the 365 observations -- 48% of the subset was one taxon, because
*Girella nigricans* is heavily detected at this site. That is the mechanism
working as designed (guaranteed means guaranteed), but if a sentinel is common
it will crowd out the random stratum. Either raise `SUBSET_N` or point
`SUBSET_ALWAYS_TAXA` at a narrower list than the full sentinel set.

### First END-TO-END subset run, 2026-09-17 (PtConception 12S, Steps 8-10)

Reused the completed `PtConMifishSchulte_*` checkpoints read-only; wrote only under
`PtConMifishSchulteSub_*` in a scratch `OUT_DIR`.

**Rule 1 held across three runs.** Every reuse-prefix checkpoint still carries its
2026-09-14 mtime, the real 977-entry review cache is still 977 entries, and no subset
artifact was written into the project directory.

**Result:** 365 observations -> 3,551 posterior rows -> 365 consensus rows -> 45 unique
candidate sets reviewed, 0 unreviewed residue -> 363 rows surviving the plausibility
filters, 28 unique taxa, exported with `subset_run = TRUE` in the CSV and a six-field
`taxaid_subset` stamp on the checkpoint.

| stage | cold | warm (identical inputs) |
|---|---:|---:|
| `review_assignments()` | 151 s, ~19,900 tokens, 5 LLM calls | **0.0 s, 0 tokens, 45/45 cache hits** |
| `scientific_to_common()` | 2,207 tokens | cached |

#### A correction worth carrying: when the review cache actually hits

It was claimed earlier in this work that pointing a subset run at a full run's review
cache would make the review "near-free". **That is wrong as stated.** The first subset run
got **0 of 45 hits** against a copied 977-entry cache.

`review_assignments()` builds its key from a `.shared` prefix -- `target_group`, `marker`,
`data_type`, `use_candidates`, and the context's NAMES AND VALUES -- plus EVERY column of
`taxa_info` for that row. So a cache entry is reused only when the review context and the
consensus row are both identical. A subset run that RECOMPUTES consensus from reused
likelihoods will not generally reproduce the full run's `taxa_info`, and any difference in
`REVIEW_CONTEXT` (even a field renamed `site` -> `geography`) changes every key. That is
correct behaviour -- context changes the verdict -- not a bug.

**To actually get a free review in a subset run**, reuse the CONSENSUS as well as the
likelihoods and keep the context byte-identical:

```r
consensus_final <- readRDS(.reuse_path("consensus_final"))   # not recomputed
# ... identical REVIEW_CONTEXT, target_group, marker, data_type ...
```

Otherwise budget ~5 LLM calls per ~45 candidate sets (~20k tokens for 365 observations),
which is cheap but is not zero.

#### Four template bugs this run found

None was reachable by parsing, by the dead-call sweep, or by the argument checker.

1. `flag_watch_candidates()` rejects an empty `watch_taxa`, and `INVASIVE_TAXA` ships as
   `character(0)` -- an unguarded call stopped the run at Step 8g. A NEW USER would hit
   this on their first attempt with nothing wrong in their own edits.
2. Step 9's overview selected `reviewed[, c(..., "posthoc_assessment", ...)]`, a column
   replaced 2026-07-30. Selecting a missing column with `[` is a HARD error.
3. Step 10 recomputed common names in a block that was broken three ways: it passed the
   whole `REVIEW_CONTEXT` list to `location` (error), would have collided into
   `common_name.x/.y` if fixed, and re-spent tokens on what Step 9 already had. Removed.
4. Neither `review_assignments()` nor `scientific_to_common()` passed `llm_fn`, relying on
   auto-detection that does not fire in a plain `Rscript` session -- this ecosystem's own
   documented footgun. Both now pass `.llm_fn_` explicitly.

Bugs 1 and 3 share a shape the argument checker CANNOT catch: the argument NAME is valid
and only the VALUE is wrong. A value-level checker is the obvious next tool; the cheaper
answer is that a template has to be RUN.
