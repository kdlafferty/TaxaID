# Critical fix-quality review + pre-code-review changelog

**Written 2026-09-05**, closing out
`ecosystem_docs/REENTRY_PROMPT_critical_fix_review_and_changelog.md`. Covers the 5 branches
merged to `main` since the last full review pass (`kernel-priors`, `local-corroboration`,
`ncbi-screen-robustness`, `undetected-evidence-mixture`, `uprank-downrank-consistency`),
plus the same-day cache-management branch. Two deliverables, per the reentry doc's own
framing: (1) a curated changelog grouped by theme, for an actual code review to read
instead of raw commit noise; (2) a skeptical re-read of the fixes themselves, hunting for
narrow/special-cased patches.

**Status: done.** Three small, low-risk fixes were made along the way (see "Fixes made
during this pass" below); nothing structural was changed.

---

## Part 1 — Curated changelog, by theme

### Theme A: Kernel-based prior estimation (replaces/supplements the GLMM path)

- `estimate_kernel_priors()` + `calibrate_kernel_bandwidth()` (TaxaExpect): site-centered
  distance-kernel prior estimator, replacing single-grid-cell GLMM priors. Validated on
  GreatLakes (Lamar precision 0.748 -> 0.868).
- `apply_undetected_evidence(pricing = "curve")`: Good-Turing/Chao-based pricing for
  unobserved-taxon evidence, replacing the earlier linear "blend" design. Validated on
  GreatLakes (precision 0.853, +4 species strictly additive).
- Per-group curve pricing (2026-09-04): a multi-group kernel fit (`sampling_group_col`) can
  now be priced per detection-process group instead of erroring outright. Three guards
  (support floor, singleton cap, group-wise pooled fallback), all confirmed to fire on the
  real 10-group PtConception 18S fit. Single-group fits verified byte-identical to the
  pre-change behavior (max |delta| = 0 on the GreatLakes checkpoint).
- `plot_theta_surface()` (new): KDE prior-field map for the kernel path, replacing
  `plot_theta_map_interactive()` (which has nothing to draw for an opaque kernel `site_id`).
- GLMM path formally deprecated (gentle, once-per-session `inform()`, not archived) --
  still load-bearing for PtConception/Mugu until their kernel migration lands.

### Theme B: BLAST-based reference-quality screening (TaxaMatch)

- `evaluate_reference_accessions()` + `reference_label_verdict.R` family: per-accession
  BLAST-based screening producing `hierarchy_flag`/`reference_action`/`label_confidence`.
- Local corroboration (2026-09-03): `corroborate_references_locally()` cross-checks a
  flagged accession against the SAME dataset's own match candidates -- catches cases where
  a wider NCBI search misses a real conspecific deposit. **Cache version bumped
  (`v5_amplicon_query`)** because the query itself changed (primer-stripped amplicon, not
  primer-inclusive span) -- a real, load-bearing change (a 169bp amplicon-only deposit was
  being out-scored by full-length relatives and never reaching NCBI's top-100 list).
  `migrate_reference_cache()` ships alongside it specifically so old caches aren't silently
  invalidated without a path forward.
- Long-sequence/throttle robustness (2026-09-01): feature-table-guided extraction fallback,
  a hard `max_query_len` cap (`"not_evaluated_oversized"` verdict), length-aware BLAST
  batching, `prioritize_uncached`/`retry_insufficient`.
- `verify_removal_candidates()` (2026-09-04): the answer to the `max_hits` truncation
  finding -- re-audits only the accessions actually marked `"remove"` at a wider `max_hits`
  before that destructive action is taken. Deliberately does NOT change the production
  default (`max_hits = 20` stays, since raising it would re-BLAST ~3,000 cached rows across
  four caches for a truncation effect that explains only ~35% of the `insufficient` verdict
  population).
- `label_confidence`/`n_independent_top_matches == 0` fix (2026-09-04): a zero-partner row
  no longer scores exactly 0.500 (a coin-flip artifact of the fallback default) -- now `NA`
  with `reference_action = "untested"`. Real effect: 98 rows across 4 real caches moved
  `caution` -> `untested`.
- `add_slash_taxon()` order-invariance fix (2026-09-04, TaxaAssign but same theme): the
  irreducibility signature hashed candidates in POSTERIOR order rather than sorted order,
  so one biological unit arriving with candidates in a different order on two observations
  was silently treated as two distinct units, both non-irreducible. Recovered a
  Lamar-confirmed grass carp detection (7,453 reads) that had vanished from GreatLakes
  output. Monotone (rows can only move FALSE -> TRUE); verified on the real run
  (538 -> 577 irreducible, 39 recovered, 0 lost).
- Two further real recovery bugs found chasing the SAME grass carp case (2026-09-04):
  `convert_taxonomy_backbone()` wasn't re-verifying a hybrid-formula label's cleaned
  maternal-parent spelling (`"idellus"` vs `"idella"`, splitting one species into two
  candidates); `review_assignments()`'s output-normalization regex didn't recognize the
  unresolved-candidate-set annotation form, silently dropping 113/885 GreatLakes rows.

### Theme C: Undetected-evidence mixture redesign (TaxaExpect/TaxaAssign)

- Presence-mixture reframing of `apply_undetected_evidence()`/`compute_posterior()`: `w`
  read as `P(locally present | evidence)`, moment-matched `n_eff`, mixture-aware posterior
  sampling. Real bug found along the way: `join_priors()`'s blanket singleton-parity
  promotion had been erasing the entire graded evidence design (3,326 rows promoted to
  exact singleton parity regardless of their actual weight); scoped by cause, reducing
  promotion to 112 rows and lifting species-resolved observations 33 -> 103.
- `update_prior_from_consensus()` soft confirmation update (D7): replaces a hard
  `min_confirmation_confidence` gate with a leave-one-out, power-prior-discounted (a0=0.25)
  soft aggregation. Validated: beats the hard gate on every axis tested on real GreatLakes
  data (co-detections 236->238, precision 0.66->0.71).
- `check_inat_range()` gains `name_match` (assembly-time, never cached stale); every
  prior-elevating consumer now gates on it -- closes a real fuzzy-misresolution risk
  (Gasterosteus gymnurus resolving to G. aculeatus, a different species).

### Theme D: Cache management, robustness, and cleanup

- `download_gbif_occurrences()` (2026-09-05): verify-before-cache + retry for truncated
  zips (a real one was silently cached as complete and failed every re-run), self-healing
  cache hit, `allow_prompts = FALSE` default (closes a real hazard: `utils::menu()` reads
  stdin, and RStudio queues a sourced script's remaining lines as menu answers -- a live
  cache prompt swallowed ~600 lines of a real workflow on 2026-09-04).
- `taxafetch_clear_cache()`/`taxalikely_clear_cache()`/shared `TaxaTools::
  list_cache_files()`/`report_and_clear_cache()`: one-time 17GB cache cleanup, plus ongoing
  tooling. TaxaMatch's reference-evaluation cache was deliberately EXCLUDED from this same
  fix after closer inspection -- it's a structurally different, cumulative, asymmetric-TTL
  cache where "congruent" verdicts are permanently valid by design; a directory-scan-and-
  delete tool would destroy exactly what that design protects.
- `resolve_barcode_marker()` (2026-09-02): a registered primer-variant term (e.g.
  `"COI-Folmer"`) is correct for primer/length resolution but unindexed by NCBI, so a query
  built from it silently matched nothing -- confirmed live (Leptocottus COI: 0 hits broken
  vs 23 fixed). The two SILENT consumers (`audit_barcode_coverage()`,
  `suggest_unreferenced_species()`) were worse than the one that at least crashed.

### Theme E: Terminology/naming audit (no functional change)

- `uprank-downrank-consistency` branch: full-monorepo audit of "uprank"/"downrank" usage
  against the documented convention. **Null result** -- every one of 190 hits across ~40
  files, including the two specifically-suspected spots, already followed the convention
  correctly. Recorded here specifically so a future session doesn't re-run this exact audit
  believing it's still an open question.

---

## Part 2 — Critical assessment: the 6 flagged candidates

### 1. `verify_removal_candidates()` false-rescue mitigation vs. `max_hits` truncation

**Verdict: RESOLVED, and it's the right resolution.** This was flagged as an open tension
in the reentry doc; it turned out to already have been addressed on 2026-09-04, one day
before this review. The design explicitly does NOT change the production default
(`max_hits` stays at 20, in `params_key`, so raising it would invalidate ~3,000 cached rows
across four real caches) -- instead it targets the one place truncation causes irreversible
harm (an accession actually being removed) with a wider-window audit before that action.
Read `veto_truncation_probe.R`'s own numbers (8/15 veto-critical accessions flip
FALSE->TRUE at `max_hits=100`; one real PtCon `"remove"` accession becomes unremovable)
before assuming the tension is fully closed -- the tool answers "should THIS specific
removal proceed," not "is 20 the right default," which the doc's own commit message
states plainly.

### 2. `apply_undetected_evidence()`'s multi-group `sampling_group` requirement

**Verdict: SOUND, verified against the one real call site that exercises it.** Read
`PtConceptionWorkflow_18S_2_single_site.R` directly (not just the CLAUDE.md summary):
the one real curve-pricing call against a multi-group fit (line ~975, invasive-watch
priors) passes `sampling_group = WATCH_SAMPLING_GROUP` with `WATCH_SAMPLING_GROUP <-
"fishes"` explicitly named, and carries an inline comment telling a future maintainer
exactly what to do if the watch list ever widens beyond fish ("either split the call per
group or add a `sampling_group` column to watch_evidence"). This is the "explicit failure
over a silent guess" design working as intended, not a `stop()` a user works around by
disabling the mechanism. Two OTHER real calls in the same workflow (domestic/food priors,
and the GLMM-path parallel block) deliberately use a SINGLE-group model object instead
(`kernel_pooled_fit` / `.domestic_food_model <- model_fits[["birds_mammals"]] %||%
model_fits[[1]]`) with an explicit comment explaining why (domestic/food priors are a
"transport branch" with no detection process of its own, so group-pricing doesn't apply) --
this is a genuine design choice, not an accidental single-group escape hatch.

### 3. Hardcoded accession/taxon-name conditionals

**Verdict: CLEAN, confirmed by direct grep, not just spot-checking the two cases already
known.** Searched all 9 packages' `R/` directories for (a) `accession/taxon_name/species
%in% c("...")` patterns and (b) every specific accession ID named in this review's own
source material (`KJ135626`, `MZ605481`, `AY850362`, `MN883227`, `OQ846263`, `KM057996`,
`HM561627`, `OQ846041`, `KM057967`). Every hit in executable code is either a roxygen
`@examples` block using SpeciesNet's own generic placeholder categories
(`"empty"`/`"human"`/`"vehicle"`) or a comment/docstring referencing a real motivating test
case -- zero hardcoded conditionals branch on a specific accession or taxon name anywhere.
The discipline documented for the two cases already checked (`KJ135626`/`MN883227`) holds
ecosystem-wide.

### 4. `chao_missing = f1^2/(2*f2)` hypersensitivity

**Verdict: MITIGATED, not solved -- and that's a defensible stopping point for now.** The
underlying formula's sensitivity to small `f2` counts (measured 1.9x-137x across counting
radii on real 18S data) is real and unchanged. What has shipped since the reentry doc was
written: `kernel_budget_sensitivity()` (2026-09-03) surfaces the sensitivity directly rather
than hiding it behind one number; the per-group curve-pricing guards (2026-09-04) include a
singleton cap that binds specifically when `f1 < 2*f2` (the exact regime where the formula
misbehaves worst). Neither of these changes the formula itself -- there is still no
floor/smoothing on `chao_missing` when `f2` is thin. Worth a dedicated statistical decision
(not an engineering fix) if this keeps surfacing on new datasets, but the diagnostic +
guard combination is a reasonable interim position rather than a narrow patch.

### 5. `posterior_consensus()` empty-`rank_system` crash

**Verdict: FIXED this session (see below).** Low-risk per the reentry doc's own
pre-approval -- the fix only changes behavior for an input that previously crashed
unconditionally (an empty `rank_system_eff` can only ever hit `.find_lca()`'s
`rev(rank_system)[[1L]]` and fail), so there is no working call path this could regress.

### 6. `add_slash_taxon()`'s "not plausible species binomials" warning

**Verdict: Documentation fixed this session; the underlying warning is correctly firing
on legitimate data, not a bug.** The function's own `@note` attributed this warning to a
single cause (GBIF genus/family-rank query artifacts) and told readers to fix it upstream
via `filter_gbif_quality(require_species = TRUE)`. On real GreatLakes/PtConception 12S
data, the warning fires on genuine `unreferenced_genus`-type fallback hypotheses from the
sequence/BLAST pathway (bare genus names like `"Perca"`/`"Ictalurus"`/`"Fundulus"`) with no
GBIF involvement at all -- following the documented advice would have sent a reader
chasing a GBIF setting that has nothing to do with the real cause. Fixed by broadening the
`@note` to name both causes and how to distinguish them (`hypothesis_type`), rather than
building a new mechanism to auto-classify or suppress the warning -- the warning's own job
(flag anything non-binomial reaching slash-name formatting) is still correct; only its
causal attribution was wrong.

---

## Fixes made during this pass

Both are documentation-or-guardrail-only; neither touches a formula, threshold, or
production default, per the reentry doc's own "what NOT to do" guidance.

1. **`TaxaAssign::posterior_consensus()`** (`R/posterior_consensus.R`): an empty
   `rank_system_eff` (auto-detection finding zero rank columns, e.g.
   `TaxaLikely::evaluate_likelihoods()`'s own output) now `cli::cli_abort()`s immediately
   with guidance to pass `rank_system` explicitly, instead of crashing ~500 lines later
   inside `.find_lca()` with a cryptic `"subscript out of bounds"`. New regression test
   added (`test-posterior_consensus.R`). `devtools::test()` 716/0/1 (up from 714),
   `devtools::check()` 0/0/0, reinstalled.
2. **`TaxaAssign::add_slash_taxon()`** (`R/slash_taxon.R`): the `@note` and the runtime
   warning's own guidance now name TWO distinct causes of a non-binomial name reaching
   `plausible_taxa` (a real GBIF data-quality artifact vs. an expected genus-level fallback
   hypothesis), instead of only the GBIF one -- see candidate 6 above.
   `devtools::test()`/`check()` clean, reinstalled.

Neither required a `.rs.restartR()` + full ecosystem reinstall -- only `TaxaAssign` itself
changed, and no other package's tests touch these two functions' error/warning paths.

---

## What this pass did NOT do (explicitly out of scope, per the reentry doc)

- Did not change `max_hits`'s production default, the false-rescue veto logic, or the
  `chao_missing` formula itself -- all three remain open tradeoffs for the user/a domain
  expert to weigh in on, not engineering calls.
- Did not re-verify every one of the ~15-20 real fixes across the 5 branches against its
  own `git show` diff line-by-line -- time-boxed to the 6 explicitly flagged candidates
  plus a full-ecosystem grep sweep for the narrow-fix PATTERN (hardcoded conditionals),
  which is the highest-value generalizable check this pass could do quickly. If a deeper
  per-commit audit is wanted, it would need its own session.
