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
