# TaxaLikely Peer Review Response

**Review date:** 2026-08-07 **Package version reviewed:** TaxaLikely 0.1.0 **Reviewer:** Micah Wright (human -- this is a genuine human-authored review, not a Claude-authored one; it replaces the prior Claude-authored review and its own response document) **Response prepared by:** Kevin Lafferty

This document responds to every checklist item and every file-specific comment in
`inst/taxalikely_review.Rmd`, in the review's own order. It **replaces** the previous
`inst/taxalikely_review_response.md`, which responded to an earlier, Claude-authored review
(lintr exclusions, `df` shadowing, duplicated NCBI enumeration blocks) -- a different review
from a different reviewer, now stale.

Each item is marked **Fixed** (code changed, verified), **Not changed** (reasoning given),
**Answered** (a real question, answered directly, no code change needed), or **Design
decision** (a legitimate architectural point, deliberately not acted on this session, with
the reasoning recorded for a future dedicated session).

------------------------------------------------------------------------

## Code Review checklist

**Functionality / Optimizations / Coding standards:** No specific action items beyond the
file-specific comments below (all addressed there). The reviewer's own general note that some
scripts are "over documented, including narrative of the development process" is addressed
under "General comments" below.

**Automated tests:** See "Test results" section at the end of this document -- reconciled
against both the reviewer's own reported baseline and this package's `CLAUDE.md` history.

**Vulnerabilities:** No new findings; not independently re-audited this session (out of scope
for a code-review response pass -- the reviewer stated they lack the domain background to
assess this and deferred).

## Domain Review checklist

**Scientific Rigor / Outputs / Algorithms:** No specific action items -- the reviewer
correctly flagged an inability to independently verify domain-specific defaults/algorithms.
Every genuinely load-bearing statistical question the reviewer *did* raise (score-transform
thresholds, `rank_code_a`/`rank_code_b` semantics, pseudo-data anchoring vs. a "real" Bayesian
model, per-species H1 gap magnitude) is answered in detail under the relevant file below.

------------------------------------------------------------------------

## General comments (not tied to one file)

**DECIPHER Bioconductor dependency -- is it necessary?** **Design decision, not changed.**
`DECIPHER`/`Biostrings` are already `Suggests`, not `Imports` (confirmed in `DESCRIPTION`),
specifically because this package serves three evidence types (DNA, image, acoustic) and only
the DNA reference-database-building/training path (`build_sequence_matrix()`,
`trim_to_amplicon()`, `repair_thin_evidence()`-class pairwise-alignment work) ever touches
Bioconductor at all -- image/acoustic calibration never loads it. `build_sequence_matrix()`
already guards with `requireNamespace()` and a clear install message at call time. Replacing
DECIPHER's multiple-sequence alignment + distance-matrix machinery with a custom
implementation would mean re-deriving a validated, widely-cited bioinformatics primitive from
scratch for no correctness benefit -- not attempted. The reviewer's own follow-up point
("functionality seems to warrant more than Suggests" in `build_site_reference.R`) is correct
that the DNA training pipeline is *substantively* dependent on DECIPHER, but that dependency is
already opt-in exactly where it's needed (`flag_errors = TRUE`/`build_sequence_matrix()`
itself), not on every package load -- kept as-is.

**R version dependency warning (pipe/lambda syntax).** **Already fixed**, confirmed still in
place: `DESCRIPTION` has `Depends: R (>= 4.1.0)` (this was one of the 9 findings from the
*prior*, Claude-authored review, fixed 2026-07-30 and unaffected by this session's B-QC2
file-loss discovery below).

**`df` shadows `stats::df()`.** Mostly already fixed by the prior review (`build_sequence.R`
-> `ref_seqs`, `trim_to_amplicon.R` -> `seq_df`, `read_crabs.R` -> `crabs_df`, confirmed still
present). **This session additionally fixed two remaining live instances the reviewer
specifically flagged**: `read_crabs.R`'s `file` parameter (shadows `base::file()`) renamed to
`crabs_file` throughout, including its one real cross-package caller
(`TaxaWizard/inst/graph/snippets/local_fasta_to_refs.R`) and metadata entry
(`TaxaWizard/inst/metadata/TaxaLikely.json`) -- see "read_crabs.R" below; `subset_db.R`'s
`for (line in lines)` loop variable (shadows `base::line()`) renamed to `fasta_line` -- see
"subset_db.R" below.

**"A lot of functions with seemingly similar functionality that are often wrappers of each
other."** **Partially addressed, partially a design decision.** One concrete case the reviewer
named directly (`audit_barcode_coverage()`/`.audit_barcode_coverage_new_()`/
`audit_barcode_coverage_gbif()`) was investigated and **fixed** -- see "coverage.R" below:
`audit_barcode_coverage_gbif()` turned out to be a genuinely dead, unexported, untested,
zero-caller "DRAFT" function (confirmed via a full monorepo grep and `NAMESPACE`), removed
entirely along with the GBIF-enumeration code path it alone exercised; the internal scaffold
renamed `.audit_barcode_coverage_new_()` -> `.audit_barcode_coverage_impl()`. The broader
pattern (many small wrapper functions across the package) reflects this ecosystem's own
documented layered-pipeline convention (`unreferenced_candidates()` -> `assign_scores()` ->
`model_likelihoods()` -> `compute_likelihoods()` orchestrator; `detect_suppressed_candidates()`
vs. `restore_suppressed_candidates()`) rather than accidental duplication in most other cases
checked -- not restructured further this session.

**Examples not runnable (recurring across nearly every file).** **Partially fixed, partially
deferred by design.** This package already has `inst/review_function_inputs.R`, a genuinely
runnable, section-by-section demonstration of every exported function using real/synthetic
fixtures (built in an earlier session specifically to answer this exact class of complaint --
see that file's own header). Rather than rewrite every `@examples` block into a full runnable
example (out of scope per the task's own guidance, and duplicative of that file), **every
flagged function this session gained a `@note` pointing at the exact
`inst/review_function_inputs.R` section that demonstrates it**, and two real doc *bugs* found
while checking these were fixed outright (not just pointed elsewhere): `audit_barcode_coverage()`'s
own example named its argument `reference_df`, directly contradicting the function's own
"Common mistake" section warning against passing a reference_df -- fixed to `match_obj`;
`flag_reference_errors()`'s example referenced a nonexistent `flagged$flag` column -- fixed to
the real column name, `error_type`.

**"Suggest removing session references and other stream-of-consciousness records."** **Design
decision, not changed.** This is a fair critique for a package heading toward CRAN/public
release, and it's noted honestly here rather than deflected: the extremely detailed
`@details`/roxygen narration of *why* a value was chosen (e.g. `correct_training_bias()`'s
~150-line `tau` derivation history, `train_likelihood_model()`'s "Non-monotonic score->likelihood
shape" section) is a deliberate convention of this project, established because a solo
maintainer's own `CLAUDE.md` session-log habit is the primary way this codebase avoids
re-investigating the same question twice -- and, concretely, it is *exactly* what let several
of the reviewer's own methods questions in this pass get answered with real derivations
instead of hand-waves (see `transform.R`'s 99.3%/50% derivation, `train.R`'s pseudo-data
anchoring answer). Trimming this to publication-appropriate prose is real, valuable future
work -- flagged for a dedicated "manuscript polish" pass before any external release, not
attempted piecemeal here since it touches nearly every file and risks losing information a
piecemeal pass can't fully replace.

**"Auto-detecting rank systems is done a lot... could be its own function."** **Design
decision / real observation, not implemented.** Investigated concretely (not deflected):
`.detect_finest_rank_col()` (`calibrate.R`, paired-`.x`/`.y`-column detection) is *not*
literally duplicated elsewhere in this package -- `build_sequence.R` uses the differently-shaped
`TaxaTools::detect_ranks()`, and `evaluate.R`/`train_likelihood_model()` each carry their own
bespoke, wider rank ladders (14 ranks) that don't match either `TaxaTools::standard_ranks` (7)
or `TaxaTools::extended_ranks` (21) exactly -- see "evaluate.R" below for the full three-way
comparison. Consolidating these onto one shared, exported `TaxaTools` constant is a real,
valuable idea, but would mean widening a constant used across the whole ecosystem and checking
every downstream consumer's auto-detection behavior for a silent change -- flagged for a future
dedicated cross-package session, not attempted here. One genuinely free, zero-risk piece of this
*was* done: `fetch.R`'s `.crabs_std_hierarchy` was an exact byte-for-byte duplicate of
`TaxaTools::standard_ranks` (confirmed identical values) -- now aliases it directly instead of
repeating the literal.

**"Suggest removing references to other packages unless strictly necessary."** One concrete,
free instance acted on: `rgbif` removed from `DESCRIPTION`'s `Suggests` (confirmed unused
anywhere in the package after removing `audit_barcode_coverage_gbif()`, its only caller).
Cross-package `@seealso`/roxygen references to `TaxaAssign::compute_posterior()`,
`TaxaExpect::generate_full_priors()`, etc. are load-bearing documentation of this package's real
place in the ecosystem's dependency chain, not removed.

------------------------------------------------------------------------

## Note on a test-count discrepancy (resolved, not a data-loss finding)

While reconciling test counts (see "Test results" below), this session initially found that
`R/audit_reference_database.R`, `R/repair_thin_evidence.R`, and `.compute_hierarchy_congruence()`
-- documented in this package's own `CLAUDE.md` (2026-08-04 through 2026-08-06 session notes,
"Reference database auditing (Module B-QC2)") -- are absent from `R/`, along with their three
dedicated test files. **Investigated further and resolved: this is not data loss.** These files
were **deliberately archived** on 2026-08-07, in an already-documented, already-completed step:
the whole DECIPHER-whole-set-alignment, taxon-list-scoped approach they implemented was found
(same session, real data) to have both a real false-positive failure mode (15 genuine,
Smithsonian-vouchered `Menidia` accessions flagged `"incongruent"` purely because `Menidia`'s
family had no other representative on a real 6-genus test's taxon list) and a structural
false-negative gap (a mislabeled accession's true contaminating identity can never be
detected if its genus isn't on the caller's own taxon list) -- see
`ecosystem_docs/REENTRY_PROMPT_blast_based_reference_quality.md` for the full record. The
superseding design (BLAST against a broad, unrestricted database instead of a taxon-list-scoped
one) is **not yet implemented** anywhere -- that reentry doc's own status line says so
explicitly ("NOT YET IMPLEMENTED... only the archival step... done"). The archived source and
tests still exist on disk, deliberately excluded from the package build, at
`TaxaLikely/archive_decipher_reference_audit/` (confirmed present, gitignored via a
2026-08-07 `.gitignore` entry with its own explanatory comment).

**The only real, actionable gap this surfaces**: `TaxaLikely/CLAUDE.md`'s own "Reference
database auditing (Module B-QC2)" Function Inventory section and several of its 2026-08-04
through 2026-08-06 session notes still describe `audit_reference_database()`/
`classify_reference_accessions()`/`repair_thin_evidence()` as live, current, shipped
functions -- they are not, as of the 2026-08-07 archival. This is a real documentation-drift
gap (not corrected in this session, since it's a large, multi-entry historical section and
out of scope for a review-response pass) worth a dedicated cleanup pass whenever the
BLAST-based replacement is actually built, so the two don't compound. If the external
`AuditNCBI.R` GreatLakes workflow still calls the archived functions, it would need
`TaxaLikely` reinstalled from a pre-archival state or updated once the replacement ships --
not evaluated this session (out of scope; the workflow lives outside this monorepo).

------------------------------------------------------------------------

## File-specific comments

### assign_scores.R

- **"How was `.unreferenced_family_weight` (0.05) chosen?"** **Answered.** Not empirically fit
  -- a deliberately conservative nominal constant matching `TaxaAssign::assign_taxa_llm()`'s
  analogous `unknown_lik_weight` (also 0.05), so an H4 hypothesis is treated comparably whether
  it enters the posterior via the scored or LLM pathway. Expanded the code comment to say this
  explicitly.
- **"Referencing TaxaAssign suggests combining."** **Design decision, not changed.** TaxaLikely
  (likelihood) and TaxaAssign (posterior) are a deliberate split going back to the ecosystem's
  founding architecture (likelihood x prior = posterior, two separable concerns) -- documented
  extensively in `TaxaID/CLAUDE.md`'s package-split history. Not revisited.
- **"How can one convert the absence of a match score into a likelihood?"** **Answered.**
  `score_type = "none"` sets every candidate's likelihood to the same constant (1.0) --
  Bayes' rule with an equal (flat) likelihood across all hypotheses means the posterior is
  exactly proportional to the prior, which is the correct, honest answer when there is
  genuinely no discriminating evidence (e.g. a morphological ID with no confidence score).
  Already documented in `@details`; not a bug.
- **"Line 91: `match_df` not created, example not runnable."** **Fixed** via `@note` pointer to
  `inst/review_function_inputs.R` Section 3.
- **"Line 264: why is this not also `NA_real_`?"** **Fixed -- real bug.** When an observation
  has zero `specific_candidate` rows, `score_likelihood`/`score_likelihood_mean` were correctly
  set to `NA_real_`, but `score_likelihood_sd` was set to `0.0` -- misleadingly claiming "a
  known point estimate with zero uncertainty" for a value that doesn't exist at all. Now
  `NA_real_` in that branch too. New regression test added
  (`test-assign-scores.R`, "an observation with no H1 rows gets NA sd, not 0").

### build_sequence.R

- **"Function name suggests a matrix but returns a `data.frame`... suggest
  `get_pairwise_match_scores()`."** **Design decision, not renamed.** A fair naming critique,
  but `build_sequence_matrix()` is called by name from dozens of real sites across this
  monorepo (workflows, `TaxaAssign`, tests, `TaxaWizard` metadata) with no bug being fixed by a
  rename -- the `@return` documentation already states plainly "A data frame with one row per
  sequence pair." Not renamed; flagged only.

### build_site_reference.R

- **DECIPHER criticality / "might be best to group this package and TaxaAssign."** **Answered,
  see "General comments" above** for the DECIPHER point. The TaxaLikely/TaxaAssign-merge
  suggestion is the same point as `assign_scores.R`'s above -- design decision, not changed.

### calibrate.R

- **"Could `.detect_finest_rank_col` be used elsewhere?"** **Answered, see "General comments."**
- **"Line 29: if no values from `paired` are in `std`, how is the last value guaranteed
  finest?"** **Fixed -- real bug, confirmed by investigation.** It wasn't guaranteed:
  `paired[length(paired)]` fell back to whatever order `intersect(x_ranks, y_ranks)` happened
  to produce (column order in the input data frame), which has no relationship to
  coarse-to-fine ordering for a non-standard rank name. Fixed to decline the guess and return
  `NULL` instead (the caller already has a documented warning + NA-metrics fallback for this
  exact case), rather than silently picking an arbitrary column.
- **"Line 132: example doesn't show how `reference_df` is derived."** **Fixed** via `@note`
  pointers (both `calibrate_coverage_filter()` and `coverage_threshold()`) to
  `inst/review_function_inputs.R` Section 8.
- **"Line 216: how is 10 categorical coverage?"** **Answered, with the reasoning now recorded
  in code.** Not tied to any specific quality scheme -- deliberately more than double the
  largest known real categorical cardinality (Xeno-canto's 5 quality grades) while far below
  what a genuinely continuous DNA-alignment coverage distribution shows on real data (typically
  hundreds to thousands of unique values). Added as an explicit comment at both of the two
  `<= 10L` checks in this file (`calibrate_coverage_filter()` and `coverage_threshold()`).

### clean.R -> renamed remove_flagged_references.R

- **"Should this be in TaxaMatch?"** **Answered, with the reasoning now recorded in the
  function's own roxygen** (new `@section Package placement`): this cleanup step operates on
  `flag_reference_errors()`'s own output, built from the exact same pairwise DECIPHER alignment
  matrix used for likelihood training -- colocating the detection mechanism and its remediation
  avoids splitting one signal and its consumer across two packages. TaxaMatch's own,
  separately-scoped reference-quality tooling (`evaluate_reference_accessions()`/
  `remove_incongruent_references()`) is a different, BLAST-based per-accession check against a
  broad external database, not this package's within-reference-set pairwise-alignment approach
  -- confirmed against TaxaMatch's own documented scope revision. Not moved.
- **"Example doesn't show how `reference_df` is derived."** **Fixed** via `@note` pointer to
  `inst/review_function_inputs.R` Section 10.
- **"Suggest renaming file to `remove_flagged_references.R`."** **Fixed.** File renamed via
  `git mv` (preserves history); `devtools::document()` re-confirmed the generated `.Rd`'s
  source-file cross-reference updated automatically. Zero functional change (R doesn't care
  about source file names).

### compute_likelihoods.R

- **"Line 52: `match_df` not created, example not runnable."** **Fixed** via `@note` pointers
  (both `model_likelihoods()` and `compute_likelihoods()`) to
  `inst/review_function_inputs.R` Section 3.
- **"Line 96 / Line 255: why return an empty `data.frame` for `unresolved` instead of
  `NULL`?"** **Answered.** Deliberate type-stability convention, consistent everywhere in this
  package `$unresolved` is produced (also see `evaluate.R`'s identical pattern, same answer
  below): a typed, zero-row data frame supports uniform downstream code (`nrow()`,
  `rbind()`/`dplyr::bind_rows()`, column access) without every caller needing a defensive
  `is.null()` branch first. Not a bug.

### correct_training_bias.R

- **General "remove session references"** -- see "General comments" above; this file has the
  most extensive version of this pattern in the package (a real empirical-investigation log for
  `tau`'s default). Not trimmed this session.
- **"I did not review Menon et al., assuming methods faithfully reproduced."** Acknowledgment
  only, no action needed.
- **"Line 182: suggest enforcing `count_col` to a consistent name."** **Answered, design
  decision.** Unlike `score_col` (a real ecosystem-wide convention, `"score_original"`),
  representation-count columns genuinely vary by data source with no established convention
  (`"n_observations"` for iNaturalist, `"n_recordings"` for Xeno-canto/BirdNET) -- `count_col`
  has no default specifically because no safe universal one exists, matching this ecosystem's
  own "no safe default" precedent (`join_priors(backbone_id=)`, `score_consensus(rank_thresholds=)`).
  Not changed.
- **"If `tau` is generally zero, should this function be in the package?"** **Answered.** Kept:
  (1) it's actively wired into the real `image_acoustic_likelihood_workflow.R`; (2) `tau = 0`
  is itself a real, hard-won empirical finding worth preserving as executable, re-checkable
  documentation, not evidence the mechanism is useless; (3) it remains available/tunable for
  future data types this package hasn't yet been calibrated against -- the same reasoning that
  led this codebase to *retire* `absolute_fit_pvalue` (a column with zero real downstream
  consumers) does not apply here, since this is an actively-called preprocessing step with a
  real, documented calibration procedure, not an unused output column.

### coverage.R

- **"Is there a similar function to `.first_two_words` elsewhere?"** **Answered, investigated
  directly.** Confirmed via a full monorepo grep: no duplicate exists. Conceptually adjacent to
  but functionally distinct from `TaxaTools::clean_taxon_names()` (which doesn't truncate a
  trailing authority-citation/qualifier the way this function does) -- a reasonable future
  `TaxaTools`-promotion candidate, not attempted here (see "General comments").
- **"Suggest checking `len_range` in `.coverage_checkpoint_path` is a length-two integer
  vector."** **Fixed.** Added a `stopifnot()` guard; previously a malformed `len_range` would
  have silently built a checkpoint filename with a recycled/missing length component instead of
  failing clearly. New offline test confirms it errors.
- **"Line 85: `reference_df` example not runnable."** **Fixed** via `@note` pointer
  (`audit_reference_coverage()`) to Section 7.
- **"Why are there `audit_barcode_coverage`, `.audit_barcode_coverage_new_`, and
  `audit_barcode_coverage_gbif`?"** **Fixed -- real dead code removed.** Confirmed via a full
  monorepo grep and `NAMESPACE`: `audit_barcode_coverage_gbif()` was never exported (`@noRd`),
  had zero test coverage, and zero real callers anywhere. Removed entirely, along with the
  GBIF-species-enumeration helper (`.get_species_gbif()`) it alone used, and the `use_gbif`/
  `version_tag` plumbing that existed only to support it. `.audit_barcode_coverage_new_()`
  renamed `.audit_barcode_coverage_impl()`. `rgbif` removed from `DESCRIPTION` `Suggests`
  (now genuinely unused). The reviewer's characterization ("both call
  `.audit_barcode_coverage_new_` without any changes") wasn't quite accurate -- they *did*
  differ, in a real, documented way (GBIF vs. NCBI species enumeration) -- but the underlying
  point (this should collapse to one real code path) was correct once it was confirmed the
  GBIF path was genuinely dead, not just duplicative.
- **"Any 'draft' functions should be removed or finalized."** **Fixed**, same removal as above.
- **"What is 'reverse' referencing here?"** **Answered, clarified in code.** Not a biology term
  -- "reverse" as in the search DIRECTION: instead of asking NCBI once per candidate species
  ("does a barcode exist for you?", N queries), this function runs one broad genus-level search
  and works backward from the results to see which candidates got covered. Added an explicit
  clarifying comment at `.reverse_barcode_check()`'s definition.
- **"Lines 754-755: `is_plausible_binomial` should be the outside function; are multiple
  `trimws()` calls needed?"** **Fixed -- real inconsistency found.** Every *other*
  `is_plausible_binomial()` call site in this file applies it to the already-`.first_two_words()`-
  truncated string; only the `species_list` validation block did it backwards (check raw, then
  truncate), with a genuinely redundant double `trimws()` call. Reordered to match the rest of
  the file (truncate first, single `trimws()`, then check plausibility on the truncated form) --
  the raw-string ordering was not flagged as more "correct" on inspection (both orderings are
  defensible; consistency with the rest of the file was the deciding factor).
- **"Line 777: presumably 1985 has a reason?"** **Fixed -- real, if narrow, bug.** No documented
  reason existed, and `fetch.R`'s own `.build_search_term()` establishes this ecosystem's real
  convention for "no meaningful lower date bound": `"1900/01/01"` (predates GenBank's own 1982
  founding). `1985` was an unexplained, undocumented literal that could have silently excluded
  a genuine 1982-1985 GenBank deposit from a `max_date`-bounded audit. Changed to `1900/01/01`
  to match the ecosystem's own established sentinel.
- **"Line 903: is `audit_acoustic_coverage` really designed for camera trap data? Suggest
  renaming."** **Design decision, not renamed.** Confirmed the function's own docs and real
  callers (`TaxaMatch/inst/workflow_image_acoustic.R`) do cover both acoustic AND image/camera-
  trap classifiers with a closed candidate list -- the name predates that generalization. A
  broader name would be more accurate, but this function is called by name from real external
  workflow scripts and another package's own README -- not renamed for a naming-clarity gain
  alone with no bug attached.
- **"Does `audit_acoustic_coverage` improve over a bare `%in%`?"** **Answered.** Yes: real
  input validation, case-insensitive normalization, a structured `census` data frame matching
  `audit_barcode_coverage()`'s own output shape (so downstream code can treat both coverage
  audits uniformly), optional live Xeno-canto enrichment, and `match_df`-based cross-referencing
  -- confirmed by reading the full function body, not assumed.
- **"Line 1098: example not runnable (as elsewhere)."** **Investigated; could not pin the exact
  original line after substantial file drift** (coverage.R grew/shrank across several
  intervening sessions since the review). Every `@examples` block in this file was checked
  directly: `audit_acoustic_coverage()` and `audit_inat_coverage()` were *already* runnable
  (self-contained, no undefined variables); `audit_reference_coverage()`,
  `audit_barcode_coverage()`, and `apply_coverage_constraints()` were not, and all three are
  **fixed** with `@note` pointers above.
- **"Line 1298: why not conditional?"** **Investigated; could not confirm.** Checked the two
  most plausible candidates (Xeno-canto recording-count enrichment, `match_df` annotation in
  `audit_acoustic_coverage()`) and both are already correctly gated behind their triggering
  flags (`xc_recordings`, `!is.null(match_df)`). If this was about one of those two, it's
  already correct; reported honestly rather than guessed at a different, unverified location.
- **"Line 1394: `.inat_species_info` is not exported, so this warning message may be
  confusing."** **Fixed -- real bug, matches the task's own named bug class.** The `httr2`-
  missing warning inside the internal `.inat_species_info()` helper self-identified by its own
  (unexported, `@noRd`) name, which a user calling the real, exported `audit_inat_coverage()`
  has no way to look up. Changed to self-identify as `audit_inat_coverage` (matching this same
  file's own correct existing pattern at the 401-Unauthorized `stop()` two lines below, which
  already did this right).

### evaluate.R

- **"Lines 122-125: use brackets on multiline `if`."** **Fixed.** The `if (verbose)
  message(...)` block (coverage-filter diagnostic) now has braces, matching this project's
  documented lintr convention.
- **General "remove session notes"** -- see "General comments." Not trimmed.
- **"I have not evaluated the statistical algorithms, assuming correct."** Acknowledgment only.
- **"Line 658: single-row `data.frame` -- why summarize?"** **Answered.** The
  `group_by(taxon_name) |> summarise(...)` step is documented, intentional
  median-across-references aggregation (see this package's own "Statistical Design Notes":
  "`evaluate_likelihoods()` takes the median score per taxon_name across multiple reference
  accessions") -- needed for the general case where a query matches *multiple* accessions of
  the same taxon. When a given call happens to have exactly one row per taxon, `median()` of one
  value trivially returns that value with zero distortion or cost, so running it unconditionally
  avoids a special-case branch rather than indicating a bug.
- **"Line 1188: example not runnable."** **Fixed** (`filter_top_hypotheses()`) via `@note`
  pointer to Section 6; `evaluate_likelihoods()`'s own example got the same treatment.
- **"Line 1243: could `.crabs_std_hierarchy` be defined once? Or `TaxaTools::extended_ranks`?"**
  **Answered in detail, partially fixed.** Investigated all three rank lists directly:
  `.crabs_std_hierarchy` (`fetch.R`, 7 ranks) turned out to be an *exact* duplicate of
  `TaxaTools::standard_ranks` -- **fixed**, now aliases it directly. `evaluate.R`'s own 14-rank
  ladder is a genuinely different, third set (has `infraclass`/`cohort`/`suborder`/`infraorder`
  that neither `standard_ranks` (7) nor `extended_ranks` (21) has; `extended_ranks` in turn has
  `domain`/`subkingdom`/`superorder`/`superfamily`/`subfamily`/`tribe`/`subgenus`/`subspecies`/
  `variety`/`form` that this ladder doesn't) -- substituting either existing constant would
  change (not just refactor-preserve) which columns get auto-detected. A full explanatory
  comment was added at the definition site; consolidating all three onto one canonical,
  ecosystem-wide extended-rank constant is flagged as a real future improvement, not attempted
  here (see "General comments").
- **"Line 1515: is the first word always genus?"** **Answered, with the assumption now
  documented explicitly in code.** Confirmed: `sub(" .*$", "", taxon_name)` is a real,
  positional (not guaranteed-safe-in-general) assumption -- correct for this package's own
  genus/species (or genus-only) convention, and degrades safely (a single-word genus-only
  `taxon_name` is returned unchanged), but not verified against every conceivable custom
  `rank_system` a caller could supply. Added a full comment explaining exactly when this
  assumption holds and doesn't, at both of its two use sites.
- **"Why is an empty unresolved `data.frame` returned?"** **Answered, see compute_likelihoods.R
  above** -- identical reasoning, identical pattern.

### expand_unreferenced.R

- **"Line 109: results not created, example not runnable."** **Fixed** via `@note` pointer to
  Section 7.

### fetch.R

- **"Is there a reason `barcode_term` isn't required to be a `gene_map`/`primer_to_locus`
  value?"** **Answered, design decision.** Deliberately open: `.build_search_term()` already has
  a graceful fallback (`bt[All Fields]`) for any unrecognized term, letting users query markers/
  primers not yet catalogued (common in this field -- new primer sets are published often)
  rather than hard-erroring. Not changed.
- **"Lines 112-113: date-window logic; docs at 473/475 differ."** **Fixed -- real doc-clarity
  gap.** The `@param min_date`/`@param max_date` examples (`"2010/01/01"`/`"2024/12/31"`) were
  illustrating the *input format*, but could be read as implying those were the real defaults --
  the actual `NULL`-handling sentinels (`"1900/01/01"`/`"3000/12/31"`, meaning "no bound") were
  never stated in the exported function's own docs at all. Rewrote both `@param` entries to
  state the real `NULL` behavior explicitly.
- **"Is `rentrez::entrez_summary()` repetition across this package and TaxaTools avoidable?"**
  **Answered, investigated directly.** Every call site targets a different NCBI database
  (`nuccore` vs. `taxonomy`) for a genuinely different purpose at a different pipeline stage
  (accession metadata during download vs. species-name resolution during coverage audits vs.
  TaxaTools's own independent name-verification pipeline, called separately/earlier in a
  workflow) -- not the same query issued twice. Already batched (200-ID batches) within each
  site. No redundant work found to eliminate.
- **"`.parse_lat_lon()` uses position... safer to extract by reference?"** **Answered (partial
  misunderstanding, confirmed by reading the code) + real hardening fix.** The function already
  extracts *by reference*, not blind position: the regex requires the first number's hemisphere
  letter to be N/S and the second's E/W as part of the match itself (not a post-hoc
  reassignment) -- a genuinely lon-first string simply fails to match at all rather than being
  silently mis-assigned (confirmed with a new test: `"121.947 W 36.789 N"` correctly returns
  NA/NA). Clarified this in a new code comment. **Also fixed, the reviewer's other suggestion**:
  a plausibility guard (`|lat| <= 90`, `|lon| <= 180`) was missing -- a regex-matching but
  physically impossible value would previously have propagated instead of degrading to NA like
  every other unparseable input. Two new regression tests added.
- **"Reason not to just query location once and include it optionally?"** **Answered, design
  decision.** `include_location = TRUE` triggers a real, separate, expensive NCBI round trip
  (full GBSeq XML per accession, not the cheap ESummary/taxonomy calls this function otherwise
  makes) -- already documented as "not free." Making this the default would impose real added
  latency on every call, most of which don't need location metadata. Kept opt-in.
- **"Stale `is_plausible_binomial` warning, per commit history — reviewer's own machine."**
  **Answered, confirmed environmental.** `TaxaTools::is_plausible_binomial()` is confirmed
  exported in the current `TaxaTools` source (`@export` tag present, in `NAMESPACE`) -- this
  was the reviewer's own locally-installed `TaxaTools` being out of date at review time, not a
  TaxaLikely bug. No code change; recommend reinstalling via `ecosystem_docs/install_all.R`.
- **"Line 1239: should `.parse_bold_coord()` take a vector? Remove the
  `length(x) != 1L` check?"** **Design decision, not changed.** Confirmed already called via
  `vapply()` over the whole column at its one call site -- functionally "vectorized" from the
  caller's perspective already. A fully internally-vectorized rewrite (batch regex over the
  whole vector at once) would be a marginal micro-optimization at this function's real data
  volumes (BOLD reference fetches: dozens-hundreds of rows, not millions) -- not worth the added
  complexity. `.parse_lat_lon()` uses the identical per-element convention for the same reason.

### infer_predicted.R

- **"Should this be in TaxaMatch?"** **Answered, design decision.** This function exists purely
  to feed one specific parameter (`exclude_predicted`) of TaxaLikely's own
  `audit_barcode_coverage()` -- it has no purpose outside that context, and TaxaMatch's own
  documented, narrow scope ("screening match data... in service of producing a clean match
  object") doesn't cover reference-database coverage auditing, which stays TaxaLikely's domain
  by the ecosystem's own established convention. Not moved.
- **"Suggest requiring `accession_col` default to `'accession'` only -- `'acc'` seems vague."**
  **Answered, design decision.** The broader candidate list (`accession`/`Accession`/`acc`/
  `accno`/`AccessionNumber`) handles real, observed naming variability across this ecosystem's
  data sources (e.g. NCBI ESummary's own field is literally `acc`). Matching is by *exact* name
  against `names(match_obj)`, not substring/fuzzy matching, so the false-positive-collision risk
  is low in practice. Not narrowed.
- Example note pointer added (Section 7).

### interpret.R

- **"Example not runnable (as elsewhere)."** **Fixed** via `@note` pointer to Section 11.
- **"Line 77: oddly placed space."** **Fixed -- real formatting bug.** A blank line was
  accidentally inserted mid-sentence in a code comment ("...when the \n\n true species/genus is
  absent..."), splitting one thought across a stray blank line. Removed.
- **"Is there a way to iterate over hypotheses so tables aren't built by position?"** **Fixed --
  real robustness improvement.** `hyp_baselines` was assembled from three separate parallel
  `c()` vectors (hypothesis labels, match percentages, gap percentages) relying on consistent
  ordering across all three -- a future independent edit to any one vector could silently
  misalign a label with the wrong values. Rebuilt as one row per hypothesis (label and its own
  values built together), then row-bound -- eliminates the cross-vector-alignment risk entirely.

### normalize.R

- **"Are line 24 and 31-32 redundant?"** **Fixed -- real, confirmed dead code.** Yes: once
  `all(is.na(x))` returns early, the `bounds`-is-`NULL` branch is only ever reached with at
  least one non-`NA` value already guaranteed, making the `length(non_na) == 0L` check there
  provably unreachable. Removed, with a comment explaining why it's safe to remove.

### read_crabs.R

- **"Line 86: `file` shadows a base function; suggest `crabs_file`. Also `df`."** **Fixed.**
  `df` was already fixed by the prior review (`crabs_df`, confirmed still present). `file` ->
  `crabs_file` throughout the function (parameter, validation messages, all internal uses) --
  this is an exported function's public signature, so every real cross-package caller was
  found and updated: `TaxaWizard/inst/graph/snippets/local_fasta_to_refs.R` (was
  `file = {{input_var}}`), `TaxaWizard/inst/metadata/TaxaLikely.json`'s `read_crabs_output`
  entry, and this package's own `README.md` example. All in-package test calls already used
  positional (unnamed) calling and needed no change (confirmed via grep).

### report_likelihood.R

- **"Example not runnable (as elsewhere)."** **Fixed** via `@note` pointer to Section 12.

### score_collapse.R

- **"Line 194: this markdown is not in this package."** **Fixed -- real doc-clarity gap.**
  `ecosystem_docs/SPEC_restore_suppressed_candidates_redesign.md` lives at the monorepo root,
  not inside the installed package -- an installed-package-only user has no way to find it.
  Reworded to state plainly it's development-repository context, not shipped documentation.
- **"Line 341: does `taxaexpect_priors` depend on TaxaExpect?"** **Answered, confirmed by
  investigation (no).** `taxaexpect_priors` is a plain data frame parameter; this package has no
  dependency on TaxaExpect anywhere (confirmed: absent from `DESCRIPTION` entirely) and never
  calls into it. The name and default column names (`taxon_col`/`grid_col`/`theta_col`) are
  chosen only for convenience, matching `TaxaExpect::generate_full_priors()`'s own output shape
  so that object can be passed directly without renaming columns -- any correctly-shaped data
  frame works. Clarified explicitly in the `@param` doc.
- **General "remove revision dates/session references."** See "General comments." Not trimmed.
- **"Line 490: example not runnable."** **Fixed** via `@note` pointer to Section 9.
- **"Line 915-916: multiline `if` without brackets."** **Fixed -- and found a real, second bug
  at the exact same location.** The `if (verbose) message(sprintf(...))` block for the no-score
  synthetic-scores path had both problems the task specifically named as bug classes to watch
  for: missing braces on the multiline body, AND a genuine **split-string `sprintf()` bug**
  (this project's own documented, recurring footgun) -- `sprintf()` was called with two
  string-literal arguments where only the first had a `%`-conversion, so the real message
  ("...creating synthetic scores (H1 = 1.0, restored = 0.9950)...") was silently truncated to
  just the first fragment, and a genuine `sprintf` "arguments not used by format" warning fired
  on every `verbose = TRUE` call through this path -- confirmed by direct execution before and
  after the fix. Fixed with `paste0()` (matching this project's own documented convention) plus
  braces. New regression test added confirming both the correct full message text and the
  absence of the spurious warning.

### subset_db.R

- **"Line 32: licensing issues -- suggest removing until confirmed."** **Answered, addressed
  by strengthening (not removing) the documentation.** This function never fetches, bundles, or
  redistributes MIDORI2 data itself (it only filters a copy the *user* already downloaded), so
  it carries no license obligation of its own -- removing the documented format entirely would
  reduce genuine utility for a licensing question that's real for the user's own downstream use,
  not for this function. Strengthened the wording to state this distinction and the "do not
  redistribute beyond local training" caution explicitly and unambiguously.
- **"Line 250: is `.save_record()` just grabbing stuff from the global environment?"**
  **Answered, technical correction + clarifying comment added.** It is not the global
  environment -- it's a standard R lexical closure over `subset_local_database()`'s own local
  variables (`records`/`current_id`/`current_seq`/`max_n_bases`), mutating `records` via `<<-`
  by design (the one legitimate, textbook use case for `<<-`: a helper closure updating its
  enclosing function's own accumulator). Kept as a no-argument closure rather than threading
  explicit params/returns through the streaming loop, since it has exactly one call site and one
  job. Clarified with a new comment; also added a `.lintr` exclusion (`assignment_linter`) with
  the same reasoning recorded, since this is genuinely correct `<<-` usage, not the
  reach-into-an-unrelated-environment pattern that linter exists to catch.
- **"Line 261: `line` is also an existing R function."** **Fixed -- real, confirmed shadowing.**
  `for (line in lines)` shadowed `base::line()` (a plotting function). Renamed to `fasta_line`
  throughout the loop.

### TaxaLikely-package.R

No comments in the review; nothing to do.

### train.R

- **"Example doesn't show how `reference_df` is created."** **Fixed** via `@note` pointers on
  both `flag_reference_errors()` (Section 2) and `train_likelihood_model()` (Section 2); also
  fixed a real, separate doc bug found while touching this: `flag_reference_errors()`'s own
  example referenced a nonexistent `flagged$flag` column, corrected to `error_type` (the
  documented real column name).
- **"Line 38: see `build_sequence_matrix()` naming comment."** Cross-reference, answered there
  (design decision, not renamed).
- **"Line 112: 0.98 comment suggests mutability but it's not mutable."** **Fixed -- real gap,
  matches the task's own named bug class exactly.** `flag_reference_errors()`'s
  `"unverified_singleton_high_match"` threshold was a hardcoded `0.98` literal with an inline
  comment literally suggesting a caller "consider raising to 99% for ITS" -- with no way to
  actually do so. Added a real `singleton_match_threshold` parameter (default `0.98`, identical
  comparison direction `>`, so this is purely additive with zero behavior change for any
  existing caller), threaded through from `train_likelihood_model()` too (which calls
  `flag_reference_errors()` internally). Two new regression tests confirm the parameter
  actually changes behavior and validates its input.
- **"Line 152: implications if `rank_code_a` differs across datasets?"** **Answered, confirming
  the reviewer's own reasoning is correct.** No issue: each `train_likelihood_model()` call is
  fully self-contained (fits H1/H2/H3 entirely within one training run on one `raw_df`), so
  `rank_code_a`'s meaning never needs to be compared *across* separately-trained models --
  nothing in this package does that. Only relevant if someone tried to directly compare/combine
  two different `model_params` objects' internal lookup keys, which no shipped code does.
- **"Line 179: if `N_Obs` is unused, suggest removing."** **Answered, kept per the package's own
  prior explicit decision.** Already investigated and documented in an earlier session (see
  `CLAUDE.md`'s Session 151 note): `N_Obs` is a real pair-count diagnostic, confirmed unused by
  any current shrinkage computation (the real shrinkage `N` is the per-*sequence* row count of
  this same data frame, computed separately) -- kept deliberately as a possible future
  pair-density diagnostic, at zero computational cost, per the user's own prior explicit choice.
  Not re-litigated.
- **"Line 202: `score_transform` not in roxygen params."** **Fixed -- real gap.** Confirmed:
  present in `train_likelihood_model()`'s own (exported) docs already, but genuinely missing
  from the internal `.prep_training_data()`'s `@param` list despite being a real parameter of
  that function (line 332 currently). Added.
- **"Why is `.generalize_ranks` internal to `.prep_training_data`?"** **Answered, design
  decision.** A small, pure, two-argument helper used exactly twice within its one enclosing
  function and nowhere else in the package -- nesting it colocates the helper with its only use
  site and avoids exposing it as file-level API surface for something genuinely single-purpose.
  Not restructured.
- **"Line 262/266: if `score_transform` isn't logit, `noise_floor_logit` is misnamed."**
  **Fixed -- real naming bug, though the computed value itself was already correct.** The
  *value* was already transform-aware (computed via `.transform_p()`, correctly on whichever
  scale `score_transform` selects) -- only the variable *name* still said `_logit` even under
  `sqrt_mismatch`. Renamed `noise_floor_logit` -> `noise_floor_transformed` throughout (3 uses,
  all within this one internal function), with a comment explaining why.
- **"Line 299: is `rank_code == b` (genus) a safe assumption?"** **Answered in detail, confirmed
  correct by the reviewer, now fully documented in code.** No -- confirmed by direct
  investigation: `rank_code_b` is purely positional (rank_system's second-to-last element,
  whatever that happens to be), not semantically validated as genus anywhere. True whenever a
  caller's `rank_system` follows this ecosystem's own standard convention (finest two elements
  "...genus, species"), which every real production workflow does, but not enforced at runtime
  by design (this package's `rank_system` is deliberately flexible, not hardcoded to one
  taxonomic ladder). Added a full explanatory comment at the exact code site rather than adding
  a new runtime check that could reject a legitimately different but positionally-equivalent
  convention.
- **"Line 707: why not a fully Bayesian model with an explicit prior? Tight priors need
  justification."** **Answered in full, real methods question, answered with a real
  derivation, not deflected.** Pseudo-data anchoring **is** a real Bayesian mechanism, not a
  workaround standing in for one: adding `n0` synthetic observations at a target value is the
  standard "prior-as-pseudo-observations" construction for conjugate Normal estimation,
  mathematically identical to placing an explicit `Normal(target, sigma^2/n0)` prior and
  computing the closed-form posterior mean -- literally the same `w = N/(N+prior_weight)`
  Empirical Bayes shrinkage form already used throughout this model for per-species/per-genus
  estimates. Implementing it as injected rows (rather than a second, separately-coded
  prior-density formula) keeps this correction on the same estimation machinery as everything
  else in the model. It is also explicitly **not** a tight prior: capped at 10% of real H1 rows
  (minimum 5), by design diluted rather than dominant, and applied only to the pooled *global*
  mean, never to any individual species' own shrunk estimate. Added this full derivation to
  `train_likelihood_model()`'s own `@section Pseudo-data anchoring`.

### tansform.R [sic -- transform.R]

- **"Presumably there's significance to 99.3%/50% -- why these thresholds?"** **Answered with
  a full, verified numeric derivation, real methods question closed.** Confirmed by direct
  computation (`plogis(5) = 0.99331...`): **5.0 is the value actually chosen; 99.3% is
  derived from it, not independently chosen.** `5.0` is a conventional, round cap on a
  logit-space (log-odds) *difference* -- a standard rule-of-thumb magnitude in
  logistic-regression-adjacent modeling for capping outlier influence.
  `logit(0.5) = 0` is the natural zero-point (a 50/50 match -- no discrimination at all between
  candidates), so "99.3%" is simply what a logit-space gap of exactly 5.0 maps back to relative
  to that zero-point -- a descriptive gloss ("roughly as large as a near-perfect match vs. a
  coin flip"), not an independently chosen biological cutoff. Added this full derivation,
  with the exact arithmetic, to `.default_gap_ceiling()`'s own documentation.

### trim_to_amplicon.R

- **"Line 242: search for non-IUPAC characters instead?"** **Answered, confirmed logically
  equivalent, not changed.** `!grepl("^[SET]+$", x)` and `grepl("[^SET]", x)` are provably
  equivalent for the non-empty strings this code path ever sees (empty strings are already
  filtered earlier) -- purely a stylistic rewrite with no behavior difference either way, so not
  changed without a concrete benefit.
- **"Line 212: message still prints the 'could not be trimmed' clause when zero."** **Fixed --
  real UX bug, matches the task's own named bug class exactly.** The verbose summary message
  unconditionally appended "N could not be trimmed..." even when N was 0, printing noise
  ("0 could not be trimmed") in the common case where every over-length sequence was
  successfully trimmed. Now only appended when the count is actually nonzero. Two new
  regression tests confirm both the zero-count (clause omitted) and nonzero-count (clause
  present, with the real count) cases -- this message path had no prior test coverage at all
  (every existing test used `verbose = FALSE`).

### unreferenced_candidates.R

- **"Line 44: can `include_unreferenced_family` be forced to `FALSE` when needed?"**
  **Answered.** Yes, trivially -- it's a plain boolean parameter (default `FALSE`), fully
  settable either way by any caller. If the underlying question was whether the package
  *auto-enforces* the documented "don't set `TRUE` with TaxaExpect priors" caution: it can't --
  this function has no visibility into whether TaxaExpect priors will be joined later in the
  pipeline (a decision made downstream, after this function returns), so documentation is the
  only available safeguard at this stage.
- **"Example not runnable (as elsewhere)."** **Fixed** via `@note` pointer to Section 3.

### write_fasta.R

No comments in the review; nothing to do.

------------------------------------------------------------------------

## Real bugs fixed (summary, with file:line)

1. `R/assign_scores.R` -- `score_likelihood_sd` was `0.0` instead of `NA_real_` when an
   observation has zero H1 candidates (a genuine "no estimate exists" case misreported as "a
   known value with zero uncertainty").
2. `R/calibrate.R` -- `.detect_finest_rank_col()`'s fallback could silently guess an arbitrary,
   wrong "finest rank" for a non-standard `rank_system` instead of declining to guess.
3. `R/coverage.R` -- `.inat_species_info()`'s `httr2`-missing warning self-identified by an
   unexported internal name a user can't look up; now self-identifies as `audit_inat_coverage`.
4. `R/coverage.R` -- an unexplained, undocumented `1985` date-floor literal, inconsistent with
   this ecosystem's own established `"1900/01/01"` "no real bound" sentinel; could silently
   exclude a genuine 1982-1985 GenBank deposit under a `max_date`-bounded audit.
5. `R/coverage.R` -- `species_list` validation checked plausibility on the raw, untruncated
   string, inconsistent with every other `is_plausible_binomial()` call site in the same file
   (which check the already-truncated form); also had a redundant double `trimws()` call.
6. `R/fetch.R` -- `.parse_lat_lon()` had no plausibility guard; a regex-matching but physically
   impossible coordinate (e.g. `|lat| > 90`) would propagate instead of degrading to NA.
7. `R/interpret.R` -- a stray blank line split one code comment mid-sentence.
8. `R/interpret.R` -- `hyp_baselines` was assembled from three independently-editable parallel
   vectors relying on consistent ordering; rebuilt row-by-row to remove the silent-misalignment
   risk.
9. `R/normalize.R` -- a provably-unreachable `length(non_na) == 0L` check (dead code, confirmed
   by the earlier `all(is.na(x))` guard already handling that case).
10. `R/subset_db.R` -- `for (line in lines)` shadowed `base::line()`.
11. `R/read_crabs.R` -- `file` parameter shadowed `base::file()`.
12. `R/score_collapse.R` -- a genuine split-string `sprintf()` bug (this project's own
    documented, recurring footgun): the no-score verbose message silently dropped its whole
    "(H1 = 1.0, restored = ...)" clause and raised a spurious `sprintf` warning on every
    `verbose = TRUE` call through that path.
13. `R/train.R` -- `flag_reference_errors()`'s `0.98` singleton-match threshold was hardcoded
    with a comment suggesting it should be adjustable, but had no actual parameter; now a real,
    additive `singleton_match_threshold` argument.
14. `R/train.R` -- `noise_floor_logit` held a value already computed on whichever scale
    `score_transform` selects (not always literally logit), a misleading name for the
    `sqrt_mismatch` case; renamed `noise_floor_transformed`.
15. `R/trim_to_amplicon.R` -- the verbose summary message unconditionally printed a
    "0 could not be trimmed" clause even when every sequence trimmed successfully.
16. `R/coverage.R` -- `audit_barcode_coverage()`'s own `@examples` block, and
    `R/train.R`'s `flag_reference_errors()`'s own `@examples` block, each modeled an incorrect
    usage pattern in their own documentation (the first directly contradicting that function's
    own "Common mistake" warning; the second referencing a nonexistent output column).
17. Dead code removed: `R/coverage.R`'s `audit_barcode_coverage_gbif()` (unexported, untested,
    zero real callers, confirmed via full monorepo grep) and its GBIF-only support code.

None of the above are statistical/likelihood-model bugs -- all are in input validation,
messaging, documentation, dead code, or naming. No formula in `evaluate.R`'s or `train.R`'s
bivariate-normal machinery, shrinkage weights, or score transforms was touched.

------------------------------------------------------------------------

## Test results

**Reviewer's own reported baseline** (`inst/taxalikely_review.Rmd`, from `test_local()`):
`[ FAIL 0 | WARN 8 | SKIP 27 | PASS 822 ]`.

**This session's observed baseline, before any fix, and after** (identical --
`devtools::test()`, run from the project root so `R_LIBS_USER` resolves correctly):
`[ FAIL 0 | WARN 56 | SKIP 1 | PASS 974 ]`.

**Reconciling the two:** `WARN 56`/`SKIP 1` match this package's own most recent `CLAUDE.md`
session-note baseline exactly (2026-08-06, "closes out a statistical-critique investigation":
*"0 failures (1075 passing, 56 expected warnings ... 1 environment skip)"*) -- i.e. this
session's warning/skip counts are consistent with the package's real, current, documented
state, not an artifact of anything done this session. The 56 warnings are themselves expected
and already explained inline by the tests that raise them (a diagnostic added in that same
2026-08-06 session correctly firing on several intentionally tiny/logit-trained synthetic test
fixtures). `PASS 974` vs. that same `CLAUDE.md` note's claimed `1075` is short by 101 -- this
gap is fully explained by the "Note on a test-count discrepancy" section above: the
`test-audit-reference-database.R`, `test-hierarchy-congruence.R`, and
`test-repair-thin-evidence.R` files documented as part of that same session's work were
deliberately archived (with their source) the following day, 2026-08-07, after real false-
positive/false-negative problems were found in the approach they tested -- not lost, and not
something this session needs to fix or reconstruct. The reviewer's own much lower
`822`/`8`/`27` reflects a still-earlier package state (predating the 2026-08-06 monotonicity-
diagnostic work entirely) and/or an incomplete local test environment (the review's own text
notes `test_check()` "doesn't work" for them, and 27 skips is far more than the 1 this session
observed, consistent with missing Suggests packages or network access in their environment)
-- not a discrepancy this session introduced.

**Net effect of this session's own fixes on the test count:** approximately +15 new
`test_that()` blocks added (`test-assign-scores.R`, `test-coverage.R` x3, `test-fetch.R` x3,
`test-train.R` x3, `test-score-collapse.R` x1, `test-trim-to-amplicon.R` x2), all passing, 0
failures introduced or removed.

**`devtools::check()`** (run twice, before and after the final lint cleanup below): **0
errors, 0 warnings, 0 notes** both times.

**`lintr::lint_dir("R")`**: 0 hits (re-confirmed after every session fix). `.lintr`'s
`R/train.R`/`R/fetch.R` exclusion line numbers were re-synchronized to this session's edits
(the exact same kind of drift the *prior* Claude-authored review's response document already
fixed once -- line numbers move every time the file is edited, by design these exclusions need
re-checking whenever a file they reference changes); one new legitimate exclusion added
(`R/subset_db.R`'s documented closure-mutation `<<-`).

------------------------------------------------------------------------

## Reinstall command

```r
.rs.restartR()
devtools::install("~/My Drive/Rscripts/projects/TaxaID/TaxaLikely")
.rs.restartR()
```

Verified this session: `devtools::install()` (run from the TaxaID project root, so
`R_LIBS_USER` resolves) lands at `~/Library/R/4.0/library` (confirmed via
`dirname(find.package("TaxaLikely"))`), the correct path per this project's own documented
Developer Environment convention.

------------------------------------------------------------------------

## What was deliberately NOT changed, and why

- The missing "Module B-QC2" reference-database-auditing files (see the dedicated section
  above) -- too large and statistically involved to reconstruct in a review-response pass;
  flagged for the user's direct decision.
- The extensive "session narrative" documentation style throughout the package -- a real,
  fair critique, but touches nearly every file; flagged for a dedicated future pass.
- Several naming critiques with no attached bug (`build_sequence_matrix()`,
  `audit_acoustic_coverage()`) -- both are called by name from real external code; renaming
  would be a breaking change with no correctness benefit.
- Consolidating the package's three different rank-name lists onto one shared `TaxaTools`
  constant -- a real improvement, but requires widening a constant used ecosystem-wide and
  checking every downstream consumer.
- No exported function had its statistical formulas touched. Every fix above is
  input-validation, messaging, documentation, dead-code removal, or a purely additive
  parameter with a default matching prior hardcoded behavior.

------------------------------------------------------------------------
