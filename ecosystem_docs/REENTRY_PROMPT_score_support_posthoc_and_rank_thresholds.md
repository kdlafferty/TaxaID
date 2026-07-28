# Re-entry prompt: score-support post-hoc signal + score_consensus() no-default rank_thresholds

Two related, real package changes came out of a long 2026-07-23 design conversation
about `diagnostics/score_floor_roc_sweep.R` and a sibling bug fix in
`TaxaLikely::train_likelihood_model()`. Both were designed and agreed with the user
but NOT implemented -- picked up here as their own task, deliberately deferred due
to session time.

**Read first, in this order:**
1. `[[project_h2_pooled_delta_hierarchy_fix]]` (memory) -- the H2 pooled-delta bug
   that was found and FIXED this same session (already shipped, not part of this
   task) plus the `score_floor_roc_sweep.R` redesign that grew alongside it. This
   task extends that redesign into real package functions.
2. `[[manuscript_figure_plan_score_calibration]]` (memory) -- a separate, unrelated
   deferred item (publication figures) from the same conversation. Not part of this
   task; don't conflate the two.
3. `diagnostics/score_floor_roc_sweep.R` itself -- the working reference
   implementation. Per-rank Youden's J (species/genus/family, each with the correct
   own TP/FP class), genus-/family-EQUAL-WEIGHTED (not row-weighted) Empirical Bayes
   shrinkage (`w = n/(n+prior_weight)`, same form as `TaxaLikely::H2_Lookup`), and a
   per-sequence best-match collapse before any pooling (mirrors `train_likelihood_
   model()`'s own `h1_data`/`congener_pool` convention). Real validated numbers:
   Sebastes vs. Halichoeres `species_support` at score=98 is 0.973 vs. 0.329.
   `family` is a structural ceiling for 12S data -- `seq_matrix` has no order/class/
   phylum columns, confirmed directly; climbing higher needs `build_sequence_
   matrix()`/the upstream taxonomy join extended, out of scope here.

## Task 1: promote species_support()/genus_support()/family_support() into a real package function

Currently script-local prototype functions in `score_floor_roc_sweep.R`, hardcoded
to one marker's `seq_matrix` path. User's decision (2026-07-23): this becomes
**informational input to `TaxaFlag::add_posthoc_assessment()`**, evaluated at the
CONSENSUS TAXON's own resolved rank -- i.e., for a given observation's winning
consensus call, does the raw score itself statistically support the rank it was
resolved to (genus/family membership of the winning taxon), independent of the
trained likelihood model. Consumed by a human expert reviewing output, or by
TaxaFlag's LLM-based review functions.

**Explicitly agreed, do not re-litigate:** this must stay ADDITIVE/informational,
never overriding `consensus_taxon`/`consensus_rank` itself -- mirrors how
`absolute_fit_pvalue` already feeds `add_posthoc_assessment()`'s `"unsupported_
rank"` category. The cautionary precedent already lived through once this
ecosystem: the `trusted_rank`/`rank_trust_basis` ladder-walk mechanism (built
2026-07-19, REMOVED 2026-07-20 -- see `[[project_rank_trust_mechanism_removed]]`)
tried something structurally similar and got pulled after a real ~30% mismatch
(computed off the wrong hypothesis) plus a downranking-cancellation bug. Don't
repeat that shape: keep the new signal as a plain continuous value a downstream
consumer reads and acts on itself, not a mechanism that recomputes/overrides
anything upstream.

**Real, NOT-yet-resolved design questions for this task:**

- **Package placement.** `absolute_fit_pvalue` is computed in TaxaLikely
  (`evaluate_likelihoods()`) and merely CONSUMED by TaxaFlag via a column name --
  strong precedent to put the new `species_support`/`genus_support`/`family_support`
  computation in TaxaLikely too (near `evaluate_likelihoods()` or `score_collapse.R`),
  not inline inside TaxaFlag. Propose this as the default; confirm with the user if
  there's a reason to deviate.
- **Where do the genus-/family-equal-weighted EB-shrunk curves live?** Computing
  them fresh from a raw `seq_matrix` every call (as the diagnostic script does) is
  wasteful and disconnected from the trained model. Strong candidate: extend
  `train_likelihood_model()` to compute and STORE these curves alongside
  `H2_Lookup` (which already has the right per-genus `n_pairs` denominators) --
  i.e., this becomes part of `model_params`, not a separate raw-data pass at
  inference time. This needs to be decided before writing code, not discovered
  mid-implementation.
- **Exact evaluation semantics at "the consensus taxon's own resolved rank."**
  Does a consumer get ALL THREE `*_support` values for every observation (so a
  reviewer can see, e.g., "resolved to species, but genus_support is also weak,
  meaning even the genus call is shaky"), or only the one matching
  `consensus_rank`? Not resolved in the design conversation -- ask the user or
  make a defensible call and flag it.
- **Data threading.** Does the observation's own raw match score survive all the
  way to wherever `add_posthoc_assessment()` runs? `absolute_fit_pvalue` already
  threads through via `posterior_consensus()`'s `winner_absolute_fit_pvalue`-style
  columns (see TaxaAssign/CLAUDE.md's 2026-07-19 note) -- the new signal likely
  needs an analogous `winner_species_support`/etc. pathway through
  `posterior_consensus()`. Trace this before assuming it's free.
- **Genus/family identity for the score-only computation.** The winning consensus
  taxon's genus/family must be resolvable at whatever point this runs -- confirm
  this is always available (it should be, but verify against real `consensus_df`
  shape, not assumed).

## Task 2: score_consensus(rank_thresholds=) loses its default

User's decision (2026-07-23): `rank_thresholds` should NOT default to the GITA/JV
values (`c(species=98, genus=95, family=90, phylum=85)`) shipped since Session 147 --
the function doesn't know the marker, or even whether the score is DNA/image/
acoustic, so no single default is safe. **Exact precedent already established in
this codebase**: `join_priors(backbone_id=)` (Session 143) -- no default, errors
immediately if omitted, with a message explaining why and what to supply instead.
Mirror that pattern exactly: `rank_thresholds` becomes required; omitting it errors
with a message pointing at two options -- (1) supply thresholds manually, or (2)
derive them from real reference data via Youden's J (pointing at whatever the new
helper function from this task is named -- see below).

**This means a second new function is needed**, not just a signature change: a
real, exported, marker-agnostic version of `score_floor_roc_sweep.R`'s per-rank
Youden's J logic (currently a hardcoded-path diagnostic script) that a user can
call to GET a `rank_thresholds`-shaped vector for their own `seq_matrix`. Natural
home: TaxaLikely (same package as `build_sequence_matrix()`/`train_likelihood_
model()`, which already produce/consume the `seq_matrix` this needs). Name not
decided -- something like `compute_rank_thresholds()`. Should probably reuse/share
code with Task 1's genus-/family-equal-weighted EB-shrinkage machinery rather than
duplicating it, since both need the same corrected per-genus/family curves.

**Real call-site rollout scope, already surveyed so this doesn't need
re-discovery:**

| File | Call | Currently passes | Breaks under new required-arg behavior? |
|---|---|---|---|
| `TaxaAssign/inst/TaxaAssign_bayesian_workflow.R` | `score_con` | `rank_thresholds = c(species=98, genus=95, family=90, phylum=85)` (explicit) | No -- already explicit, but should be revisited to use a real marker-derived value instead of the GITA/JV placeholder |
| `TaxaAssign/inst/TaxaAssign_llm_workflow.R` | `score_con_wilder` | `rank_thresholds = NULL` | **YES** -- relies on the default, will error |
| `TaxaAssign/inst/TaxaAssign_llm_workflow.R` | `score_con_thresholds` | explicit GITA/JV values | No, but same placeholder concern as above |
| `TaxaAssign/inst/TaxaAssign_llm_workflow.R` | `score_con_JV` | `rank_thresholds = NULL`, `rank_system = c("order","family","genus","species")` | **YES** -- relies on the default. Also: this call's own `rank_system` includes `"order"`, which the CURRENT default `rank_thresholds` has never had an entry for (relabeled `order`->`phylum` 2026-07-20) -- worth checking whether this variant ever behaved as its own `_JV` name implies, independent of this task. |
| `TaxaWizard/inst/graph/snippets/match_to_consensus_score.R` | templated | `rank_thresholds = {{rank_thresholds}}` | Depends on what TaxaWizard's interview flow fills in -- check whether it can currently leave this blank/rely on the function default. |

`TaxaWizard/inst/metadata/TaxaAssign.json` almost certainly needs updating too
(this ecosystem has a documented history of metadata drifting out of sync with
real signatures -- see `[[project_taxawizard_metadata_drift]]`; check it
explicitly, don't assume it's fine).

## Suggested sequence for the next session

1. Resolve the two open design questions in Task 1 (package placement + where the
   EB-shrunk curves live) with the user BEFORE writing code -- these shape whether
   Task 1 and Task 2 end up sharing an implementation or not.
2. Build the shared genus-/family-equal-weighted EB-shrinkage machinery once
   (likely extending `train_likelihood_model()`'s own output), then build the two
   consumers (the new `compute_rank_thresholds()`-style function for Task 2; the
   new `*_support` columns/function for Task 1) on top of it.
3. Wire Task 1's output into `TaxaFlag::add_posthoc_assessment()` as a new
   informational category/column, additive only.
4. Make the Task 2 breaking change, fix the two real call sites that rely on the
   default (table above), and check the TaxaWizard snippet/metadata.
5. `devtools::test()`/`devtools::check()` clean on TaxaLikely, TaxaAssign, TaxaFlag,
   TaxaWizard as touched. Update `TaxaID/CLAUDE.md`'s Recent Breaking Changes table
   (Task 2 is a real breaking change) and each touched package's own CLAUDE.md.
