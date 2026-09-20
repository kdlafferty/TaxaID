# Re-entry prompt — P7's Bayesian dry-run arm

**Written 2026-09-20 by `lafferty-45`.** P7 of
`SPEC_taxawizard_derived_context_2026_09_18.md` asked for two console dry runs:
"the score-only path **and one Bayesian path**; the generated script runs". Only the
score-only arm was built. This is the other one, deliberately left undone rather than
quietly dropped, with the reason and a cheaper design than the spec implies.

---

## STATE ON DISK (2026-09-20)

`TaxaID` repo, branch `main`, in sync with `origin/main` at `b5c34b8`.

- `diagnostics/taxawizard_dry_runs/console_fixture.R` — the harness. It already
  drives the real `workflow_engine()` through classify -> path_select ->
  parameterize, generates the script, runs the static checks, and executes the
  result. **Only ARM 1 (score-only) exists inside it.** The Bayesian arm is a second
  `run_interview()` call plus its own checks; the harness was written expecting one.
- `diagnostics/taxawizard_dry_runs/README.md` — records the score-only baseline and
  states this gap in its own words. Keep the two consistent.
- Fixtures are **gitignored**, so they are absent from a fresh clone and from any git
  worktree. Point `TAXAID_FIXTURES` at a tree that has them.

Nothing is half-built. Starting this does not require undoing anything.

---

## WHY IT WAS NOT JUST RUN

Every Bayesian route from `match_df` in the workflow graph passes through
`taxa_to_refs` (or `taxa_to_site_refs`) -> `refs_to_matrix` -> `matrix_to_model`,
and a priors branch through `taxa_to_occ` -> `occ_to_std` ->
`std_to_priors_kernel` / `dist_to_priors_by_group`. The graph's own duration
annotations for those edges are:

| edge | cost |
|---|---|
| `taxa_to_refs` | 5-30 min, live NCBI |
| `refs_to_matrix` | 1-10 min |
| `taxa_to_occ` | 1-5 min, live GBIF |
| `occ_to_std` | 1-3 min, one LLM habitat call |

So a literal reading of the spec means a 30-60 minute run with live NCBI, live GBIF
and an LLM call, every time the dry run is exercised. That is not a fast-fixture dry
run, and a check nobody can afford to run is a check that stops being run.

**The relevant fixtures already exist** and short-circuit exactly those stages:

- `ptcon12s_fast_lik_model_calibrated.rds` — a real calibrated `model_params`
- `ptcon12s_r2_fast_taxaexpect_priors.rds` — real `priors` (783 rows, named-evidence
  and anonymous-mirror mix intact)
- `ptcon12s_r2_fast_match_obj.rds` — the `match_df` from the same run

And the graph has a single-edge Bayesian tail that consumes precisely those three:

```
match_to_consensus_bayes    match_df + model_params + priors  ->  consensus
```

**But `model_params` and `priors` are NOT input nodes.** The graph's inputs are
`sequences`, `match_df`, `taxa`, `consensus_df`, `reference_df`, `occurrences`,
`birdnet_detections`, `image_classifier_output`, `local_fasta`, `images_meta`. So a
user who already has a saved model and priors *cannot express that starting point*,
and neither can the dry run. That is an observation about the graph, not a defect
this prompt asks you to fix — see OPTIONAL below.

---

## WHAT TO BUILD

Two parts. They answer different questions and neither substitutes for the other.

### Part B1 — does the engine PLAN a Bayesian path correctly? (4 LLM turns, no pipeline)

Add ARM 2 to `console_fixture.R`: a scripted user who asks for a **Bayesian**
consensus — priors and a trained likelihood model, explicitly not the score route —
and let the interview reach a complete DAG. Then run the existing `check_script()`
against it and **do not execute it**.

Acceptance:

- reaches `status = "complete"` with a DAG
- the DAG's edge ids are a real path through the graph ending in `consensus`, and
  include `match_to_consensus_bayes` **or** the
  `model_match_to_lik -> lik_prior_to_post -> post_to_consensus` chain
- all five static checks pass: parses, Step 0 present once, Step 0 edges match the
  selected path, every `Pkg::fn` a real export, no stale named arguments
- Step 0's `edges = c(...)` contains no invented id (`.keep_known_edges()` should
  already prevent this; ARM 1 proved the model *does* invent them)

Record the result in the README the way ARM 1 is recorded, including anything the
model got wrong — that is the point of the exercise.

### Part B2 — does the emitted Bayesian tail actually RUN? (no LLM, no network, seconds)

Separately, exercise `match_to_consensus_bayes` on the three fixtures above: load
the match object, the calibrated model and the priors, and run that edge's snippet
(`TaxaWizard/inst/graph/snippets/`) with its `{{placeholders}}` filled from them.

Acceptance: it executes, returns a consensus table, and the row count is consistent
with the fixture's observation count. Add it to `console_fixture.R` as ARM 2b, or as
its own small script beside it.

### What B1 + B2 together do NOT prove

They do not prove the upstream edges execute — `taxa_to_refs`, `refs_to_matrix`,
`matrix_to_model`, `taxa_to_occ`, `occ_to_std` are never run. **Say so in the
README.** A reader who sees "Bayesian arm: PASS" and assumes the whole Bayesian
pipeline was exercised has been misled, and this project has spent two days
cataloguing checks that reported on a stand-in for the thing they claimed to test.

If you want the upstream covered too, that is a third part and it costs the 30-60
minutes honestly. Run it once, record the numbers, and do not wire it into anything
that runs routinely.

---

## HOW TO RUN WHAT EXISTS

```bash
cd "/Users/lafferty/My Drive/Rscripts/projects/TaxaID"
P7_OUT=/tmp \
TAXAID_FIXTURES="$PWD/diagnostics/fast_workflows" \
Rscript diagnostics/taxawizard_dry_runs/console_fixture.R mid
```

`P7A_SCRIPT=<path>` re-checks and re-runs an already generated script without paying
for another interview. Use it while iterating on the checks.

---

## OPTIONAL, AND A SEPARATE DECISION

Adding `model_params` and `priors` as graph **input** nodes would let a real user
resume from a saved model rather than re-fetching references — the same thing that
makes this dry run expensive makes the real workflow expensive. That is a genuine
usability question, it is the user's call, and it should not be smuggled in as part
of a dry run.
