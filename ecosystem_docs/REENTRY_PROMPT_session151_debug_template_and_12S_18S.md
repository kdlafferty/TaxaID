# Reentry Prompt: Debug `TaxaID_Workflow_Template_TEST.R`, then PtConception 12S/18S workflows

**STATUS: written 2026-07-11 at the end of Session 151, before any debugging started.**
Session 151 finished the 16-item H-priority statistical soundness-review walkthrough
(`ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md`) — items 9 and 12-16, committed
and pushed as `283dd3d`. The next session's job is to go back to live-testing/debugging
`inst/TaxaID_Workflow_Template_TEST.R`, then `PtConceptionWorkflow_12S.R` and
`PtConceptionWorkflow_18S_2.R` (both outside this monorepo, at
`~/My Drive/Rscripts/eDNA/PtConception/`). This doc exists so that session doesn't have to
re-derive what changed underneath those scripts first.

**Read this before touching the workflow scripts.** Several real behavior changes landed
in packages those scripts call, some with defaults that silently produce different output
than the last known-good run — not new bugs, but real differences worth ruling in/out
before chasing something else.

---

## Reinstall first

Every touched package (TaxaLikely, TaxaMatch, TaxaFlag) needs reinstalling before any of
this matters:

```r
.rs.restartR()
source("~/My Drive/Rscripts/projects/TaxaID/ecosystem_docs/install_all.R")
.rs.restartR()
```

---

## What changed, and which real files are actually affected

Checked directly (grep) which of the three real files call each changed function, and
whether they pass explicit overrides or rely on the new default. Only two of the six
Session 151 items land on any of these three files' actual behavior — the rest are
opt-in/additive and irrelevant unless you choose to use the new parameter.

### 1. `TaxaFlag::flag_contaminant()` — contaminant_score formula changed. Affects ALL THREE files.

All three files call `flag_contaminant()` with every parameter at its default (no
`prior_weight`, no `score_thresholds` override):

- `inst/TaxaID_Workflow_Template_TEST.R:221`
- `PtConceptionWorkflow_12S.R:142`
- `PtConceptionWorkflow_18S_2.R:164`

**What changed:** `contaminant_score` used to be an unweighted mean of per-sample
proportions, with hard `0.0`/`1.0` for any taxon absent from one side (field or control).
It is now a read-depth-weighted rate, Empirical-Bayes-shrunk toward 0.5 by how many total
samples (field + control) actually detected the taxon (default `prior_weight = 2`). Scores
no longer reach an exact 0 or 1. **Concretely: a taxon that used to score exactly 1.0
because it was absent from a small number of controls will now score somewhat below 1.0**
— and depending on `score_thresholds` (default `c(0.5, 0.9)`, unchanged), a taxon that used
to land solidly in `"low"` risk could now land in `"moderate"`.

**Why this matters for debugging:** in all three files, `flag_contaminant()`'s output
directly drives a keep/remove decision —

```r
contaminant_ids <- contaminant_flags |> filter(lab_contaminant_risk == "high") |> pull(...)
decontaminated_table <- ... |> filter(!observation_id %in% contaminant_ids)
```

`"high"` risk taxa get removed either way (that classification is the least likely to flip
— it's already `score <= 0.5`, and shrinkage pulls small-n taxa *toward* 0.5, not away from
it). What's more likely to shift is the `"low"`/`"moderate"` boundary for taxa that used to
sit at an artificial exact 1.0. **If the decontaminated set differs from a prior known-good
run, check `contaminant_flags$lab_contaminant_risk` and the new `field_rate`/`control_rate`/
`n_field_present` columns before assuming something else broke** — this may be the new,
intentionally more-conservative behavior working as designed, not a bug. See
`ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md` item 15 and
`TaxaFlag/CLAUDE.md`'s Session 151 note for the full mechanism (including a real design bug
that was caught and fixed mid-implementation — worth reading if the new scores look
surprising, since the fix's own history is informative about what *not* to expect).

If the new scores turn out to be a genuine problem for real PtConception data (e.g.
`prior_weight = 2` shrinks too aggressively or not enough for this study's real sample
counts), `prior_weight` is tunable per call — this was calibrated on a small synthetic mock
fixture only, never against real PtConception read-count data.

### 2. `TaxaMatch::blast_sequences()` — `score_range` default widened 2 → 8. Affects the Template only.

`inst/TaxaID_Workflow_Template_TEST.R:118-124` calls `blast_sequences()` without an
explicit `score_range`:

```r
BLAST_annotated_ASV_table_full <- TaxaMatch::blast_sequences(
  ASV_TABLE_test,
  max_hits    = 5L,
  email       = "lafferty@ucsb.edu",
  ncbi_api_key = Sys.getenv("ENTREZ_KEY") %||% NULL,
)
```

**What changed:** the score window used to keep only hits within 2 percentage points of
each query's top BLAST hit; it now keeps hits within 8 points (still capped at `max_hits`
per query, unchanged). This means **each query can now return more candidate hits than the
same query returned in a pre-Session-151 run** — expect `BLAST_annotated_ASV_table_full` to
have more rows, and possibly more genera/species represented per `observation_id`, than
before. This is not a query-construction bug; it's the new (evidence-backed, see item 14 in
the soundness review) default deliberately retaining more real candidates so
`TaxaLikely`'s bivariate-normal model gets a chance to weigh them, instead of the BLAST
step silently deciding the case on raw percent-identity alone. If downstream steps assume a
narrow, mostly-single-candidate-per-query shape (e.g. anything that was implicitly relying
on `max_hits`-vs-`score_range` interaction to keep result sizes small), that assumption may
need revisiting.

Neither `PtConceptionWorkflow_12S.R` nor `PtConceptionWorkflow_18S_2.R` calls
`blast_sequences()` directly (grepped, confirmed) — they consume BLAST output produced
elsewhere, so this change doesn't touch them.

### 3. Everything else from Session 151 — confirmed NOT relevant to these three files right now

Checked directly, not assumed:

- **`TaxaLikely::apply_coverage_constraints()`** (item 12, `constraint_behavior` default
  `"zero"` → `"relabel"`): `PtConceptionWorkflow_12S.R:762` and
  `PtConceptionWorkflow_18S_2.R:1002` both already pass `constraint_behavior = "relabel"`
  explicitly — this call's behavior is unchanged for both. `TaxaID_Workflow_Template_TEST.R`
  doesn't call `apply_coverage_constraints()` at all (it calls `join_priors()` directly,
  bypassing the coverage-constraint step entirely). **No action needed here**, but if you
  add an `apply_coverage_constraints()` call to the Template later, know that its default
  is now the safe one.
- **`TaxaLikely::build_sequence_matrix()`** (item 13, new opt-in `barcode_term` param):
  called in the Template (`:924`) and both PtConception workflows, none pass `barcode_term`
  — purely additive, default behavior unchanged for all three. Worth considering wiring in
  (`barcode_term = BARCODE_TERM`) given the Paralabrax/amplicon-window footgun this
  parameter exists to close, but that's a deliberate follow-up, not something broken.
- **`TaxaLikely::train_likelihood_model()`** (item 9): docs-only, no behavior change at all.
- **`TaxaFlag::flag_handler()`** (item 16, new opt-in `station_metadata` param): not called
  anywhere in any of these three files.

---

## Suggested order

1. Reinstall (see above).
2. Run `TaxaID_Workflow_Template_TEST.R` from the top. Watch specifically:
   - Section with `blast_sequences()` — sanity-check candidate-row counts per query look
     reasonable, not exploded.
   - The `flag_contaminant()` step and the `decontaminated_table` filter right after it —
     compare `contaminant_flags` to expectations; check `lab_contaminant_risk` distribution,
     not just row count.
3. Once the Template runs clean, move to `PtConceptionWorkflow_12S.R`, then
   `PtConceptionWorkflow_18S_2.R`. For both, the one thing to actually check is the
   `flag_contaminant()` step's output — `apply_coverage_constraints()` is already confirmed
   unaffected.
4. If `flag_contaminant()`'s new behavior looks wrong for real data (not just different from
   before), that's a legitimate new finding — bring it back for a `prior_weight`/
   `score_thresholds` recalibration discussion rather than treating it as a regression to
   silently revert.

---

## Where the full detail lives

- `ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md` — items 9, 12-16, full
  per-item mechanism and caveats.
- `TaxaLikely/CLAUDE.md`, `TaxaMatch/CLAUDE.md`, `TaxaFlag/CLAUDE.md` — each package's own
  Session 151 note, more implementation detail than the review doc.
- `TaxaID/CLAUDE.md` — ecosystem-level Session 151 notes and the "Recent Breaking Changes"
  table (rows for Session 151 cover all six items with exact before/after values).
- Git commit `283dd3d` ("Complete soundness-review H-priority walkthrough: items 9, 12-16
  (Session 151)") — the actual diff, already pushed to `origin/main`.
