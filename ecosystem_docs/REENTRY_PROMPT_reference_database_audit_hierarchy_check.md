# REENTRY PROMPT: Reference-database audit -- hierarchy congruence + QC refinements

Status: design agreed with the user across an extended conversation (2026-08-04 to
2026-08-06), including a full critical re-design after an Opus-model architecture review
found the first version would not have caught the motivating case. Not yet implemented.
This doc is the complete, self-contained brief for whoever (human or agent) implements it
next -- written so no prior conversation history is required.

## Background / already shipped

TaxaLikely gained three new functions this same design thread, already implemented,
tested, and installed (`R/audit_reference_database.R`):

- `estimate_reference_scope(taxa, barcode_term, min_date, max_date)` -- NCBI count-only
  preflight (no fetch/alignment), reuses internal `.build_search_term()`/`.ncbi_delay()`.
- `audit_reference_database(taxa, barcode_term, rank_system, min_date, max_date,
  ncbi_backbone_id, max_sequences, cache_dir, ncbi_api_key)` -- exhaustive fetch (default
  `max_sequences = Inf`, no per-species/per-genus subsampling -- deliberately different
  from `fetch_ncbi_reference_sequences()`'s own modeling-oriented defaults), cleans the
  listed taxon name via `TaxaTools::verify_taxon_names(backbone_id = 4L)` (NCBI backbone,
  not cross-backbone reconciliation -- user's explicit choice), builds `seq_matrix` via
  `build_sequence_matrix()`, and returns ONE ROW PER ACCESSION with raw QC statistics only
  -- no categorization. Metadata (taxa/marker/dates/counts) attached via
  `attr(result, "search_metadata")`.
- `classify_reference_accessions(qc_df, mislabel_threshold, singleton_match_threshold,
  require_verified_name)` -- takes the stats-only output and derives `error_type` +
  `recommended_list` ("blacklist"/"review"/"whitelist") at a caller-chosen threshold, with
  zero recompute cost (pure function of already-fetched columns). Deliberately separate
  from `audit_reference_database()` -- see "Why separate stats from classification" below.

Also shipped: `train.R`'s `flag_reference_errors()` was refactored (behavior-preserving,
verified against its existing tests) to extract a new internal helper,
`.compute_reference_qc_stats(raw_df)`, which does the `group_by(id_x)`
summarise-to-one-row-per-accession step WITHOUT the `error_type` categorization --
`flag_reference_errors()` now calls this helper and adds `error_type` on top.
`audit_reference_database()` calls the SAME helper directly.

`devtools::test()`/`devtools::check()` were clean at each step; package reinstalled to
`~/Library/R/4.0/library`. `.lintr`'s `train.R` object-name exclusion line numbers were
updated to match the shift from the refactor.

**Not yet done, not part of this task**: updating `TaxaLikely/CLAUDE.md`'s Function
Inventory and `TaxaID/CLAUDE.md`'s top session note for the three shipped functions --
flagged to the user, deferred at their request pending real-data testing. Whoever
finishes THIS task should fold both sets of changes into one CLAUDE.md update pass.

## The problem this next phase solves

The user's actual goal: assemble a reference database for a taxon/marker, flagged for
POTENTIAL ERRORS, producing a dataframe with accession/listed taxon/cleaned taxon name/QC
scores -- then separately choose thresholds to build black/white lists. Motivating use
case surfaced mid-design: **a parasite is correctly identified morphologically (correct
label), but the sequenced DNA is actually the host's** (lab/pipeline contamination),
replicated across several individuals from the same sample.

**Two structural limits, established via a critical Opus-model design review of the first
version of this doc -- read before re-deriving any of this from scratch:**

1. **The check can only see contamination whose true source lineage is inside the audit's
   own fetch scope.** `audit_reference_database(taxa = ...)` only fetches what's asked
   for. If a user audits just the parasite taxon, the host's true reference sequences were
   never fetched at all -- there is nothing in the comparison universe to reveal the
   error, no matter how the statistics below are computed. This is a data-scope limit, not
   a statistics problem, and is NOT solved by this task -- users auditing a group with a
   known/suspected contamination source (e.g. parasites and their typical hosts) need to
   deliberately widen `taxa` to include it.

2. **A naive "top-N nearest neighbours" statistic is defeated by the exact replication
   that motivates this feature.** A first design used raw nearest-neighbour matches as a
   corroboration signal. Walking it through the motivating case: a contaminated
   accession's *nearest* matches (by `p_match`) are its own sibling replicates from the
   same contamination event (same wrong sequence, `p_match ~= 1.0`) -- they outrank the
   true host sequences in any top-N ranking. A statistic built on raw nearest neighbours
   is therefore silent precisely when replication exists, which is the defining feature of
   the motivating case, not an edge case of it. **Fixed in this version via the
   "independence" mechanism below** -- per the user's own diagnosis: intraspecific
   comparisons are not the problem (they're required for the original self/foreign gap to
   mean anything at all) -- comparisons **between accessions from the same submission
   batch** are the problem, since those aren't independent evidence regardless of whether
   they're same-species or not.

Full design-conversation record (not reproduced here, but available if reasoning needs
re-deriving): three orthogonal QC threads were identified -- (1) taxonomic hierarchy
congruence (this doc's main content), (2) sequence-similarity barcode-gap refinement, (3)
NCBI metadata plausibility + BOLD cross-referencing (both explicitly deferred, not
designed in detail, not in scope for this task).

## spider package evaluation (verified, not assumed)

`spider` (CRAN, "Species Identity and Evolution in R", actively maintained -- v1.5.3,
2026-07-13, MIT license) was investigated via live web search + reading its actual PDF
reference manual. Findings:

- `bestCloseMatch()`/`nearNeighbour()`/`threshID()` essentially duplicate
  `flag_reference_errors()`'s self-vs-foreign logic, with a richer categorical output
  (`"correct"`/`"incorrect"`/`"ambiguous"`/`"no id"`) than our current binary
  `mislabeled`/`clean` split. **Not adopted directly** -- see the dense-matrix
  incompatibility below -- but its 4-category framing is worth keeping in mind as a
  reference point for `classify_reference_accessions()`'s own category design.
- **Nothing in `spider` does rank-hierarchy congruence above genus/species.** Confirms the
  hierarchy-congruence check below is not reinventing anything that already exists.
- `spider::localMinima()` (an ABGD-style adaptive gap-threshold finder) and
  `spider::monophyly()`/`monophylyBoot()` (a lightweight NJ-tree-based check) were both
  investigated as possible additions -- **both cut from scope**, see "Explicitly out of
  scope" below for why.
- **Key incompatibility, verified by reading `build_sequence.R` directly, and important to
  get the REASON right, not just the conclusion**: `spider`'s core functions
  (`bestCloseMatch`, `nearNeighbour`, `nonConDist`, etc.) require a complete `ape::dist`
  object. It is tempting to say "our `seq_matrix` is sparse, so we can't feed it to
  spider" -- **that framing was checked by the Opus review and found wrong.**
  `DECIPHER::DistanceMatrix(aligned, type = "matrix", ...)`
  (`build_sequence.R:299-305`) already materialises a **full dense N x N matrix** before
  any sparsification happens; the `distance < max_dist` filter
  (`build_sequence.R:310`, default `max_dist = 0.25`) only sparsifies the OUTPUT TABLE,
  not the computation. Peak memory during that call is roughly **32*N^2 bytes**
  (the dense distance matrix plus two `row()`/`col()` index matrices plus three logical
  comparison matrices, all live simultaneously). This means:
  - `spider`'s dense-object requirement is not actually a *new* cost relative to what
    `build_sequence_matrix()` already pays -- a `dist` object would in fact be cheaper
    (dense matrices are symmetric; `dist` stores only the lower triangle).
  - **`audit_reference_database(max_sequences = Inf)` already has a real, undocumented
    memory ceiling, independent of anything in this task** -- back-of-envelope, N ~ 15,000
    to 25,000 sequences is roughly where 32*N^2 bytes starts to be impractical on a typical
    machine (N=20,000 -> ~12.8 GB just for this one step, on top of the
    `DECIPHER::AlignSeqs()` alignment itself, which is its own large cost at that scale).
    **This task must document this limitation** (in `audit_reference_database()`'s own
    roxygen and in `estimate_reference_scope()`'s docs, pointing the user at
    `max_sequences` as an explicit escape hatch) even though fixing the underlying
    algorithm is out of scope. Do not re-introduce the false "avoids an N^2 intermediate"
    framing anywhere in new docs -- that comment in the source refers only to the output
    table, not the computation.
  - The decision to build our own extension rather than adopt `spider`'s functions still
    stands, but for a *different, correct* reason: not "dense would cost more" (it
    wouldn't), but "we already have the dense computation done as a byproduct of
    `build_sequence_matrix()`'s own alignment step, so extending the SAME already-computed
    `seq_matrix` (sparse output table, cheap to re-aggregate) is strictly less total work
    than reshaping into a `dist` object and calling a second package's API."

## Design to implement

### 1. Widen `rank_system`'s default for the audit path only -- NOT free, real cache risk

`audit_reference_database()`'s own default changes to
`c("kingdom", "phylum", "class", "order", "family", "genus", "species")` (currently
`c("family", "genus", "species")`). `fetch_ncbi_reference_sequences()`'s own
general-purpose default is UNCHANGED (other callers don't need this).

The NCBI-query cost really is zero: `.fetch_taxonomy_map()` (`fetch.R:204-236`) always
receives the full lineage XML per accession and only discards ranks not in
`desired_ranks` -- verified directly, this part of the original claim holds.

**But do not describe this as "free" anywhere** -- `fetch_ncbi_reference_sequences()`'s
per-taxon cache key does NOT include `rank_system` (`fetch.R:815-829`: taxon, barcode,
length bounds, dates, out-of-range suffix -- nothing else), and the cached `meta` object
only carries whatever rank columns were in force when it was written. A user who has
already run any fetch (audit or otherwise) against the same taxon/marker/dates/lengths
with the narrower default will hit a **hard crash** (`undefined columns selected`,
`fetch.R:1117-1120`'s `keep_cols` subset) the first time they run the widened default
against a stale cache, since `audit_reference_database()` defaults `cache_dir` to the
same shared `tools::R_user_dir("TaxaLikely", "cache")` most other callers use. This is the
same failure class already documented in `TaxaLikely/CLAUDE.md` for the Session 159
`barcode_term` cache-staleness issue.

**Required fix, in scope for this task** (this narrowly overrides the "no changes to
`fetch_ncbi_reference_sequences()`" instinct -- the alternative is a function that
silently corrupts or hard-crashes on real stale caches, which is worse): either (a) fold
`rank_system` into the per-taxon cache key (`fetch.R`, matching the existing
`eff_min_len`/`eff_max_len`/`max_date` pattern already used there), or (b) make the
`keep_cols` subset at `fetch.R:1117-1120` tolerant of a stale cache missing newly-requested
rank columns, filling them `NA` with an explicit message telling the user to clear the
cache for a full re-fetch. Prefer (a) -- it's the same fix this exact bug class already
received once (Session 159), and a silent `NA`-fill under (b) risks a user trusting
incomplete hierarchy data without realising it's stale.

Downstream consequence once fixed: `build_sequence_matrix()` already emits
`{rank}.x`/`{rank}.y` columns generically for every rank in `rank_system` (verified in
`build_sequence.R:347-355`), so once `phylum`/`kingdom`/etc. are retained, `seq_matrix`
carries them on every pairwise row at no extra alignment cost.

### 2. Extend `.compute_reference_qc_stats()` (`R/train.R`) -- as an internal-only growth, public contract preserved separately

Add to the internal helper's output:

- `median_foreign_match` -- median (not just max) `p_match` across all
  `species.x != species.y` rows for that `id_x`. Addresses the order-statistic /
  sample-size sensitivity of `max_foreign_match` alone. **Document the truncation
  caveat explicitly**: every foreign row in `seq_matrix` is already filtered to
  `p_match > 0.75` (the `max_dist = 0.25` retention step), so this is the median of the
  *upper tail* of the foreign-match distribution, not the whole distribution -- for a
  genus with one congener at 0.99 the median is 0.99; for a genus with forty congeners
  mostly at 0.90 the median is 0.90, i.e. it can differ in either direction relative to
  `max_foreign_match` depending on how many foreign neighbours exist, not just whether
  they exist. Still a useful, cheap column -- just don't oversell what it measures.
- `n_foreign_pairs` -- count of foreign comparison ROWS behind the two match statistics
  (renamed from an earlier `n_foreign_neighbors` draft -- name it for what it actually
  counts, since it's rows, not distinct foreign taxa; a genus with 400 rows could be 3
  species or 400). If distinguishing "well-supported by many species" from
  "well-supported by many accessions of few species" matters downstream, also expose
  `n_foreign_taxa` (count of distinct `species.y` values) -- cheap, same `summarise()`
  block, include it.
- **NA convention, must be stated in the roxygen**: `max_foreign_match`'s existing code
  coerces `-Inf`/`NA` (no foreign rows at all) to `0` (`train.R:51-55`, unchanged).
  `stats::median(numeric(0))` returns `NA`. Match the existing convention: when there are
  zero foreign rows, `median_foreign_match` should also read `0`, not `NA`, so a
  downstream `case_when` doesn't silently produce `NA` verdicts by comparing `0` against
  `NA`.

**Resolving the contradiction the Opus review found** (this doc's item 2 originally said
"pure extension... `flag_reference_errors()` gains columns it doesn't use," while the
out-of-scope section said `flag_reference_errors()`'s behavior "must remain byte-identical
… its existing tests are the contract" -- both cannot be true if the columns are added to
the return value the tests check): **the internal helper `.compute_reference_qc_stats()`
gains these columns unconditionally** (it's `@noRd`, no public contract to preserve), but
`flag_reference_errors()` (the public function) explicitly trims back to its documented
column set before returning (`dplyr::select()` down to the existing
`id_x, species_x, median_self_match, max_foreign_match, n_self_neighbors, integrity_gap,
error_type` list) so its own roxygen `@return` and existing tests need zero changes.
`audit_reference_database()` keeps every column from the same helper call. This is the
one correct way to satisfy both constraints simultaneously -- implement it this way, not
by picking one constraint over the other.

### 3. New internal helper, `R/train.R`: `.compute_hierarchy_congruence(seq_matrix, reference_df, rank_system, top_n = 5L, submission_window = 5L)`

This is the redesigned core mechanism -- **read the "independence" subsection before
implementing; the naive version was wrong.**

**Independence filter (the actual fix for the replicated-contamination case).** Before
ranking partners for any `id_x`, exclude any partner `id_y` that shares the same
*submission batch* as `id_x` -- NOT the same species. Same-species comparisons from
DIFFERENT, independent submissions remain fully valid and are exactly what the original
self/foreign gap needs; only same-batch comparisons are non-independent evidence.
Determining "same submission batch," in order of preference:

1. **Submission/create date, if available.** `.fetch_summaries_batched()` (`fetch.R`)
   currently parses only `acc/title/taxid/slen/organism` from the NCBI ESummary response
   -- a `createdate`-equivalent field is very likely present in the same, already-cheap
   ESummary call for the nucleotide database (this is a standard ESummary DocSum field
   across most NCBI databases), **but this has NOT been verified live against the real
   API in this design thread -- verify it directly (a single real `rentrez::entrez_summary()`
   call, inspect the returned field names) before relying on it, exactly the discipline
   this whole design thread has required of every other "is X free" claim.** If confirmed
   present, add it to `.fetch_summaries_batched()`'s parsed columns (zero new NCBI calls,
   same batched request already made) and treat two accessions as same-batch when their
   create dates fall within a small window of each other (default a few days;
   `submission_window` here is a fallback/complementary parameter, see below -- if dates
   are available, they should be the primary signal, not accession-number proximity).
2. **Accession-number proximity, always available, zero fetch cost.** Same-submission
   batches are very commonly assigned sequential/contiguous accession numbers. Parse the
   alphabetic prefix and numeric suffix of `composite_id`; treat two accessions as
   same-batch when they share the same prefix and their numeric parts differ by less than
   `submission_window` (default `5L`). This is a heuristic, not a guarantee (real
   submission batches aren't always contiguous, and contiguous numbers aren't always one
   batch) -- document it as such. Use as the fallback when dates aren't available, or as
   a second independent signal alongside dates (treat as same-batch if EITHER signal
   says so, to be conservative about excluding non-independent evidence).
3. **Author, explicitly deferred.** Real author-level "same submission" detection needs
   the fuller per-accession GBSeq XML (`GBSeq_references`/`GBReference_authors`), which is
   NOT part of the current cheap ESummary+taxonomy fetch path -- it's the same additional
   per-accession NCBI round trip `include_location = TRUE` already pays for a different
   purpose (lat/lon). Given the memory/scale concerns already documented above for an
   exhaustive audit, do not add a second mandatory per-accession round trip in this task.
   If date + accession-proximity together prove insufficient in practice, author-level
   checking via `include_location`-style GBSeq XML is the natural follow-up, not this
   task.

**With the independence-filtered partner set established**, for each `id_x`:

- Sort remaining ("independent") partners by `p_match` descending, take up to `top_n`
  (fewer is normal and expected, especially in sparse regions of the database -- do not
  error on this).
- `finest_common_rank` -- walk `rank_system` COARSE TO FINE comparing `id_x`'s own rank
  values against the single best independent match's rank values; report the FINEST rank
  at which they still agree (the user's own framing -- "lowest common rank" -- is the
  positive statement of the same walk the first design computed as "coarsest
  disagreement"; keep whichever framing reads more naturally in the code, but be
  internally consistent, the first draft of this doc mixed the two and that caused real
  confusion in review). `NA`/`"none"` when they don't agree even at `rank_system`'s
  coarsest level (the strongest possible signal -- this is what a genuine cross-phylum
  host/parasite mismatch looks like). Skip (do not evaluate) any rank where either side's
  value is `NA` -- a missing higher-rank value is a data gap, not evidence of anything,
  and must not be silently counted as either agreement or disagreement.
- `n_independent_top_matches` -- how many independent partners actually contributed
  (`<= top_n`). This is the honest denominator, separate from raw `n_top_matches_available`
  before the independence filter -- expose both if useful for debugging, but the
  CORROBORATION statistic below must use the independence-filtered count.
- `frac_independent_below_min_congruent_rank` -- **Jeffreys-smoothed**, not a raw
  proportion (per the Opus review: a raw `k/n` is uselessly lumpy at small `n`, e.g. a
  single disagreeing partner out of one reads as "100% corroborated," which defeats the
  entire point of requiring corroboration). Use `(k + 0.5) / (n + 1)` -- the same
  smoothing convention already adopted in this package's `support_curves.R` for the
  identical "raw proportion from tiny n is overconfident" problem, do not invent a new
  one. `k` = count of independent top-N partners whose `finest_common_rank` is coarser
  than `min_congruent_rank` (see below) or `NA`/none; `n` = `n_independent_top_matches`.
  **Require `n_independent_top_matches >= 3` before this statistic is treated as
  meaningful** -- below that floor, mark the accession's hierarchy evidence as
  `"insufficient_independent_evidence"` (a distinct, honest state) rather than letting a
  smoothed-but-still-tiny-n fraction drive a verdict either way.

**Rank threshold, corrected per the user's direct biological objection to the first
draft's kingdom/phylum default**: `min_congruent_rank` defaults to `"family"`, NOT
`rank_system`'s coarsest level. Rationale, stated explicitly in code comments and roxygen
so it isn't "fixed" back to phylum by someone who didn't see this conversation: real
host-parasite pairs are very often in the SAME phylum, class, or even order as their host
(crustacean parasites of crustaceans, insect parasites of insects) -- a fixed
kingdom/phylum-level threshold would both (a) miss the motivating case when parasite and
host share phylum, and (b) is unreliable regardless, since NCBI does not populate the
literal rank `"kingdom"` uniformly (populated for Metazoa/Viridiplantae/Fungi, largely
absent for protists and all prokaryotes, which use `superkingdom`/domain instead) --
a `kingdom`-anchored default would silently never fire across large parts of the tree,
with no diagnostic. `"family"` is a defensible default because genuine congener/confamilial
confusion (the normal, expected kind of DNA-barcode ambiguity) still agrees at family;
failing to agree even at family with EVERY independent close match is a much stronger,
more specific signal of gross mislabeling/contamination than a fixed coarse-rank cutoff.
Make `min_congruent_rank` a caller-overridable parameter (some taxa/markers may warrant a
different default), but ship `"family"` as the shipped default, not phylum or kingdom.

**Vectorisation requirement (Opus review, engineering)**: this helper must be implemented
as column-wise operations over the (`group_by(id_x) |> filter(independent) |>
slice_max(p_match, n = top_n)`)-sliced table, NOT a per-row or per-accession loop over up
to 7 rank-column pairs. This package has already been bitten twice by exactly this
performance-bug class on real data (a per-candidate `%in%` scan and a per-call `sub()`
over a ~3M-row `seq_matrix`, both documented in `TaxaLikely/CLAUDE.md`'s top session
notes) -- do not add a third instance. Time this function against a real-scale
`seq_matrix` (not just the small offline test fixtures) before considering it done.

### 4. Wire into `audit_reference_database()`

Call `.compute_reference_qc_stats()` (now with its extra columns) and
`.compute_hierarchy_congruence()` on the SAME `seq_matrix` -- no second alignment, no
second fetch. `.compute_hierarchy_congruence()` additionally needs `reference_df` (or
just its `composite_id` + date/accession-number columns) to compute the independence
filter -- thread it through explicitly rather than trying to derive submission info from
`seq_matrix` alone, which doesn't carry it. Join results onto the per-accession output
alongside the existing columns. Update the function's own roxygen `@return` table.
`top_n`/`min_congruent_rank`/`submission_window` should be caller-exposed parameters
(sensible defaults per above), recorded in `search_metadata`.

### 5. Extend `classify_reference_accessions()` -- separate column, not folded into `error_type`

**Resolves the precedence question the first draft left open.** This codebase has already
run this exact experiment twice, on record: `TaxaFlag::confusion_risk_flag` was
deliberately kept as a SEPARATE additive column, explicitly not folded into
`posthoc_assessment`'s override chain, citing the `trusted_rank` ladder-walk removal as
the cautionary precedent for what goes wrong when a new signal gets folded into an
existing override chain. The one case that DID fold a new signal into a single
categorical-with-priority (`"unsupported_rank"`) fired on 0 of 606 real observations and
was later retired alongside `absolute_fit_pvalue`. Do the same thing here:

- **Do not add `"hierarchy_incongruent"` to `error_type`.** Leave `error_type`'s existing
  logic and values completely untouched.
- Add a new, separate `hierarchy_flag` column with values `"incongruent"` (the smoothed
  fraction clears the threshold), `"congruent"` (it doesn't), or
  `"insufficient_independent_evidence"` (below the `n >= 3` floor) -- a single condition,
  not the two-part gate the first draft proposed (the first draft's AND of
  `top_match_agreement_rank` + `frac_top_n_disagree_at_coarsest` was itself part of why
  the mechanism failed -- one well-specified, Jeffreys-smoothed condition is simpler and
  was shown in review to be the actual fix, not an approximation of one).
- `recommended_list` is the ONE place the two signals combine: `"blacklist"` if
  `error_type == "likely_mislabeled"` OR `hierarchy_flag == "incongruent"`; `"review"` for
  the existing review cases plus `hierarchy_flag == "insufficient_independent_evidence"`
  when nothing else already flagged it; `"whitelist"` otherwise. No information is lost,
  no precedence ambiguity remains.
- `classify_reference_accessions()`'s existing `needed <- c(...)` input validation
  (`audit_reference_database.R:377`) must treat the new hierarchy columns as OPTIONAL
  (graceful skip / `hierarchy_flag` simply absent from output) when a caller passes an
  older `qc_df` that predates this feature -- do not make them required, that would break
  every already-shipped call site with no warning.

## Explicitly out of scope for this task (do not build)

- Thread 2 (barcode-gap refinement beyond the `median_foreign_match`/`n_foreign_pairs`
  columns above) and Thread 3 (NCBI metadata plausibility beyond the date-based
  independence check above, BOLD cross-referencing) -- discussed but not designed in
  implementation-ready detail. Flag as follow-on work, don't improvise a design here.
- **`spider::localMinima()` / an adaptive-threshold wrapper -- cut entirely, not deferred,
  actively wrong direction.** The Opus review found this package already ships
  `compute_rank_thresholds()` (`R/support_curves.R`), a SUPERVISED method deriving
  per-rank thresholds from `seq_matrix` via Youden's J on genus-/family-equal-weighted,
  Empirical-Bayes-shrunk, Jeffreys-floored ROC curves, using the real known-rank ground
  truth every `seq_matrix` pair already carries. `localMinima()` is unsupervised
  density-based detection on a plain distance vector -- feeding it a difference-of-two-
  summary-statistics quantity like `integrity_gap` has no ABGD interpretation at all, and
  it would duplicate, more weakly, machinery already shipped in this same package. This
  was a real miss in the original `spider` evaluation -- corrected here.
- `spider`'s `"ambiguous"` category, and `spider::monophyly()`/tree-based checks --
  genuinely separate, underspecified threads; do not half-design them as sub-bullets of
  this task.
- Any change to `fetch_ncbi_reference_sequences()`'s own default `rank_system` or other
  existing callers' behavior -- EXCEPT the cache-key fix in item 1 above, which is
  required, not optional, given it would otherwise hard-crash real users on stale caches.
- Rewriting `flag_reference_errors()`'s own `error_type` logic or its public return
  contract -- must remain byte-identical (its existing tests are the contract); see item
  2's resolution for exactly how to add shared internal columns without touching this.
- Fixing the `build_sequence_matrix()`/`DECIPHER::DistanceMatrix()` dense-matrix memory
  ceiling itself (documenting it is in scope; redesigning the alignment step to avoid it
  -- e.g. blocked/chunked distance computation -- is a separate, larger task).
- Author-level (GBSeq XML) same-submission detection -- date + accession-proximity only
  for this task, see item 3.

## Verification bar before calling this done

- `devtools::test()` 0 new failures (existing suite, including the just-shipped
  `test-audit-reference-database.R`, must stay green; `flag_reference_errors()`'s own
  tests must be untouched given item 2's resolution).
- New tests, offline, following this package's established `local_mocked_bindings()`
  convention (see `test-audit-reference-database.R` for the pattern -- mocked
  `fetch_ncbi_reference_sequences`/`build_sequence_matrix`/`TaxaTools::verify_taxon_names`,
  hand-built small `seq_matrix`/`reference_df` fixtures rather than live DECIPHER runs).
- **The motivating-case fixture is the one that matters most and must be built from the
  actual biology, not a simplified stand-in**: >= 3 near-identical accessions sharing the
  parasite label, all from the SAME submission batch (same/close create dates and/or
  contiguous accession numbers), whose true sequence content matches real host-taxon
  accessions ALSO present in the fixture (from a DIFFERENT, independent submission) --
  assert `hierarchy_flag == "incongruent"` for the contaminated accessions. This is the
  case the whole feature exists for; do not ship without a test proving it actually works
  end to end, not just that the mechanism runs without erroring.
- **A companion true-negative fixture**: a genuinely correctly-labeled parasite accession
  whose few available independent close matches are real confamilial/congeneric relatives
  (agreement at family/genus/species) -- assert `hierarchy_flag == "congruent"`, i.e. the
  family-level default does not false-positive on ordinary DNA-barcode-level ambiguity.
- **A sparse-region fixture**: an accession with only 1-2 independent partners available
  -- assert `hierarchy_flag == "insufficient_independent_evidence"`, not a confident
  verdict either way.
- **An independence-filter fixture proving the filter actually excludes same-batch
  partners**: construct a case where, WITHOUT the independence filter, same-batch
  siblings would dominate the top-N and mask a real signal; assert the filtered version
  correctly surfaces the flag that the unfiltered version would have missed. This is the
  regression test for the specific failure the Opus review found in the first design.
- A timing check of `.compute_hierarchy_congruence()` against a real-scale (order
  10^5-10^6 row) `seq_matrix`, confirming the vectorised (not per-row) implementation.
- `devtools::check()` 0 errors/0 warnings/0 notes.
- Reinstall and verify `find.package("TaxaLikely")` resolves to
  `~/Library/R/4.0/library` (per this project's own documented Rscript-install footgun).
- Update `.lintr`'s `train.R` object-name exclusion line numbers again if the new code
  shifts them (check via `lintr::lint("R/train.R", linters = lintr::object_name_linter())`,
  don't guess line numbers).
- Live-verify (before relying on it in shipped code) whether NCBI's ESummary response for
  the nucleotide database actually includes a create-date-equivalent field, per item 3 --
  a single real `rentrez::entrez_summary()` call is enough to check field names directly.
- Document the `audit_reference_database()` dense-matrix memory ceiling (item under
  "spider package evaluation" above) in that function's own roxygen and in
  `estimate_reference_scope()`'s, pointing at `max_sequences` as the mitigation.
- Fold in the still-pending CLAUDE.md updates for ALL functions from this whole design
  thread (the three already-shipped functions plus everything built from this doc) in one
  pass at the end, per this project's own explicit end-of-session reminder convention.
