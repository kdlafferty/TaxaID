# TaxaMatch Peer Review Response

**Review date:** 2026-07-12 (file mtime) **Package version reviewed:** TaxaMatch 0.1.0
**Response prepared by:** Claude Code (Sonnet 5), 2026-07-20, at K. D. Lafferty's request

This document responds to `inst/taxamatch_review.Rmd`, which reviews 10 files (`blast.R`,
`convert_taxonomy_backbone.R`, `read_acoustic.R`, `read_image.R`, `report_match.R`,
`score_image_inat.R`, `sequence_input.R`, `standardize_match_data.R`,
`TaxaMatch-package.R`, `taxonomy_consistency.R`) and contains dozens of comments per file,
substantially larger in scope than the TaxaFetch review this document's format follows.
Every file was fixed in this pass; two items needed live verification against real external
services before a fix could be decided (see below) rather than reasoning from the code
alone. `devtools::test()`: 456 expectations, 0 failures, 0 warnings. `devtools::check()`:
0 errors, 0 warnings, 0 notes. `lintr::lint_package()`: 0 issues in every file touched this
session (verified by filtering the package-wide lint run to just those files; remaining
lints are pre-existing, in files this review did not cover). Reinstalled to
`~/Library/R/4.0/library`.

Per the review's own suggestion, 3 files were renamed to match their single exported
function: `blast.R` -> `blast_sequences.R`, `read_acoustic.R` -> `read_birdnet_output.R`,
`read_image.R` -> `read_image_classifiers.R` (holds 3 related image-classifier readers, so
named for the group rather than one function). Test file names were **not** renamed to
match (`test-blast.R`, `test-read_acoustic.R`, `test-read_image.R` still exist under their
original names) -- not required for tests to run, left as a minor optional follow-up.

A new `R/utils_shared.R` was added, consolidating patterns the review found duplicated
across `blast.R`, `read_acoustic.R`, `read_image.R`, and `score_image_inat.R` -- exactly
the cross-cutting DRY concern the review raised five separate times. It provides
`.check_pkg()`, `.extract_genus()`, `.stop_missing_files()`, `.validate_min_conf_top_n()`,
`.apply_top_n()`, `.warn_na_coercion()`, `.warn_duplicate_basenames()`, and `.fmt_time()`,
used across `blast_sequences.R`, `read_birdnet_output.R`, `read_image_classifiers.R`,
`score_image_inat.R`, and `sequence_input.R`.

------------------------------------------------------------------------

## Live verification (two items the code alone couldn't settle)

**iNaturalist CV API score scale.** The review flagged a real internal contradiction:
`score_image_inat.R` documents live API scores as 0-100, while `read_image.R`'s
`read_inaturalist_cv_output()` (reading *saved* JSON from the same endpoint) documented
0-1 and showed a fabricated `"combined_score":0.87`-style example. Resolved by calling the
real, live iNaturalist CV API (fresh token, real camera-trap photo): `combined_score`
values like 53.8, top-10 candidates summing to ~84.4 -- confirms the 0-100 scale.
`score_image_inat.R`'s doc was already correct; `read_image.R`'s was the bug, fixed (see
below).

**`exifr` GPS longitude sign.** The review's human reviewer flagged, with appropriate
uncertainty ("I should note that claude thinks the existing way is correct... However, in
testing exifr returned signed floats, so it would be best to double check"), that
`score_image_inat.R`'s EXIF sign-correction logic looked suspicious. Resolved by writing
known GPS coordinates (South latitude, West longitude) into a real image with `exiftool`
and reading them back with `exifr::read_exif()`: **`exifr` already returns signed decimal
degrees** (e.g. `-119.8489` for 119.8489 W). The existing code's manual
`if (ref == "W") lng_val <- -lng_val` therefore double-applied the sign, silently flipping
every correctly-negative Southern-hemisphere/Western-hemisphere coordinate back to
positive -- a real, confirmed bug, fixed below. This directly validates the human
reviewer's instinct over Claude's original (wrong) assessment embedded in the review file.

------------------------------------------------------------------------

## File-specific responses

### `blast.R` -> `blast_sequences.R`

**Fixed:**
- `globalVariables()` call now has an inline comment explaining why (the `pident ~ qseqid`
  NSE formula interface in `.filter_blast_hits()`); the stray duplicate `%||%` import block
  moved from the bottom of the file to the top.
- `max_target_seqs < max_hits` now issues a `warning()` (BLAST can never return enough
  hits to reach the `max_hits` cap otherwise).
- `email`/`ncbi_api_key` now default from `NCBI_EMAIL`/`NCBI_API_KEY` environment
  variables, matching this ecosystem's established `~/.Renviron`-based API-credential
  convention (documented example in `@param`).
- `report_params` attribute documented in `@return` (previously undocumented despite
  `report_match()` consuming it).
- `max_target_seqs`/`batch_size` gained real input validation (`is.numeric`/`is.na`
  checks) -- previously silently `as.integer()`-coerced with no check at all, so a
  non-numeric input would propagate as `NA` into `ceiling(seq_len(n) / batch_size)` and
  fail confusingly downstream.
- The 10 `if (!requireNamespace(pkg)) stop(...)` guards across `.blast_remote()`,
  `.blast_local()`, `.parse_blast_xml()`, `.resolve_taxonomy()`,
  `.resolve_taxonomy_by_acc()`, and `.resolve_locations_by_acc()` consolidated to
  `.check_pkg()`.
- `.resolve_taxonomy_by_acc()`'s two duplicate empty-taxonomy-data-frame literals
  consolidated to `.empty_acc_taxonomy_result()`.
- Doc additions: percent-identity-is-alignment-not-sequence-identity caveat, single-HSP
  query-coverage limitation, `max_target_seqs` BLAST-truncation bias (Shah et al. 2018,
  cited), reproducibility note (record query date / database version).

**Verified as already correct, no change needed:**
- The XML-parsing `do.call(rbind, ...)` pattern the review flagged (line numbers from an
  older file version) already collects into a list first and calls `rbind` once per
  iteration/once overall -- the recommended pattern, not the O(n²) antipattern described.
- `stats::aggregate()` + `merge()` for per-query max score: both the human reviewer and
  Claude's own embedded comment called this low-priority given hit counts are bounded by
  `max_target_seqs`; left unchanged.
- The `filtered$taxid_join`/no-`taxid_join` column-shape difference between the two
  taxonomy-resolution branches: downstream code already defensively checks
  `tc %in% names(filtered)` before reading any taxonomy column, so the "subtle merge
  artifact" risk the review flagged is already handled.

**Considered and declined (with reasoning):**
- A generic `.retry_ncbi_batch()` helper to consolidate the three near-identical
  `for (attempt in 1:3) tryCatch(...)` retry loops in `.resolve_taxonomy()`,
  `.resolve_taxonomy_by_acc()`, and `.resolve_locations_by_acc()`: a real, legitimate DRY
  win, but these functions make live NCBI network calls that are expensive to
  re-verify live within this session's scope; deferred to a session with a live-testing
  budget rather than shipping an equivalent-but-unverified refactor of code that talks to
  a real external service.
- Reducing the inter-batch sleep when `ncbi_api_key` is supplied (the review's "missed
  optimisation" note): not implemented -- uncertain whether NCBI's BLAST URL API (as
  opposed to E-utils, which the review's cited "3 req/sec with a key" figure may actually
  describe) honors a faster cadence with a key at all; getting this wrong risks an IP-level
  rate-limit ban on a production system. Left at the current, already-field-tested 11s
  cadence.
- `entrez_search()`'s `paste(batch, "[ACCN]", collapse=" OR ")` query-length risk (100
  accessions/batch): documented via an inline comment (rentrez posts the query rather than
  appending to a URL, and `batch_size = 100` has already run successfully in production per
  this package's session history) rather than changed, since no real failure has been
  observed.
- `is.integer()` vs `is.numeric()` for `max_hits`: current `is.numeric()` check +
  `as.integer()` coercion already matches what the review's own follow-up comment
  recommended ("test if numeric and convert"); left as-is.

### `convert_taxonomy_backbone.R`

**Fixed:**
- The `has_name` variable reused for two different logical vectors (flagged as
  "misleading and error-prone") -- the second occurrence renamed `has_orig_name`.
- `verify_fn(...)` now wrapped in `tryCatch()` with a clear, actionable error message
  instead of propagating whatever uninformative error the API layer produced.
- New pipe-character (`|`) pre-check on taxon names before the API call, since
  `classification_path`/`classification_ranks` are parsed on `|` -- a name containing it
  would silently corrupt rank extraction.
- New `stopifnot`-equivalent check: `verify_fn` returning duplicate `user_supplied_name`
  values now errors clearly instead of silently matching only the first occurrence.
- New lightweight sanity check: if none of `verify_fn`'s non-NA `classification_path`/
  `classification_ranks` values contain the expected `|` delimiter (and `rank_system` has
  more than one entry), warns that the response format may not match the documented
  contract.
- **Real correctness fix:** `clean_taxon_names()` is now applied to each extracted
  `target_<rank>` value, not just `matched_name` -- previously, an authority string
  surviving inside `classification_path` (format/version-dependent) could register a false
  `"changed"` collision against an already-clean original rank value naming the same taxon.
- `verbose` parameter added, gating the final "Backbone column mapping" message.
- Doc additions: `verify_fn`'s `verified` column documented as logical; `backbone_cols`
  attribute structure illustrated with a concrete example; `@return` now states
  `backbone_col`/`collision_col` are created-if-absent, not overwritten; copy-on-modify
  `@note`; homonym risk (*Morus* example) and single-name-vs-genus-cascade behavior
  documented; WoRMS-for-marine/GBIF-for-terrestrial backbone-choice guidance added;
  whitespace-only-name edge case documented (not code-changed, since fixing it correctly
  requires also changing the API lookup key, and the value of doing so for an unconfirmed
  real-world case didn't seem worth the risk).

**Declined:** the `ifelse()`-chain vectorization suggestion -- both the human reviewer and
Claude's embedded comment agreed this is low-priority for realistic (non-millions-of-rows)
`match_df` sizes; left unchanged.

### `read_acoustic.R` -> `read_birdnet_output.R`

**Fixed:**
- `top_n` validation reordered to type-check before coercion (via the new shared
  `.validate_min_conf_top_n()`), fixing the cryptic-coercion-warning-before-clear-error
  pattern flagged here and in two other files.
- Missing-file error messages consolidated via `.stop_missing_files()`.
- `as.numeric()` coercion of `Start (s)`/`End (s)`/`Confidence` now warns when a non-NA raw
  value coerces to `NA` (malformed source data, not genuinely missing).
- New `End (s) <= Start (s)` window-validity warning.
- **`observation_id` now formats `start_s`/`end_s` to a fixed 1 decimal place** instead of
  bare numeric-to-string coercion -- fixes the real cross-platform/cross-R-version ID
  instability the review flagged (`3` vs `3.0` vs `3.000000`). This is the one behavioral
  change with an existing-test update: `test-read_acoustic.R`'s expected ID string changed
  from `"..._0-3"` to `"..._0.0-3.0"`.
- New duplicate-image/recording-basename warning (when the same basename appears at
  different full paths in the `File` column) -- **found and fixed a real bug in my own
  first version of this check** during the test run: it initially flagged the *same* file
  path repeated across multiple candidate rows (legitimate combined-format data, one row
  per candidate) as a collision. Fixed to compare (basename, full path) pairs, not raw
  basenames, before warning.
- Empty-result 0-row constructors (2 duplicate literals) consolidated to
  `.empty_birdnet_result()`.
- Genus extraction now uses the shared `.extract_genus()`.
- Stale `TaxaTools::change_backbone()` doc reference corrected to the real function name,
  `convert_taxonomy_backbone()`.
- Doc additions: BirdNET `--rtype` format limitation (only default CSV supported);
  unpreserved per-recording metadata (lat/lng/week) noted; `source_file`'s differing
  meaning between the file-path and data-frame input paths clarified.

**Declined:** the "why is `file_path_sans_ext()` wrapped twice, couldn't a single `sub()`
replace it all" suggestion -- traced through deliberately: the current 3-step chain (strip
`.csv`, strip `.results`, strip `.BirdNET`) degrades gracefully for a non-canonically-named
file passed directly (not from the `.BirdNET.results.csv`-filtered directory scan), while a
single regex anchored on the exact `.BirdNET.results.csv` suffix would leave the extension
attached for anything else. Left as the more permissive (if less minimal-looking) version.

### `read_image.R` -> `read_image_classifiers.R`

**Fixed:**
- `df` (shadows the base `stats::df()` function) renamed to `animl_df` throughout
  `.parse_animl_file()`/`.pivot_wide_animl()`.
- Three duplicate 0-row empty-result constructors consolidated to `.empty_animl_result()`,
  `.empty_inat_result()`, `.empty_wi_result()`.
- `min_confidence`/`top_n` validation, missing-file messaging, top-N filtering, genus
  extraction, and the `jsonlite` availability guard consolidated via the new shared
  helpers across all three exported functions (`read_animl_output()`,
  `read_inaturalist_cv_output()`, `read_wildlife_insights_output()`).
- Duplicate-image-basename warnings added (Animl crop filenames, Wildlife Insights JSON
  keys).
- **`read_inaturalist_cv_output()`'s score-scale documentation was actually wrong**
  (`@return` claimed "(0-1)"): fixed to match the live-confirmed 0-100 scale (see Live
  Verification above), including a corrected, more-realistic `@examples` fixture (was
  `0.87`/`0.91`, now `72.4`/`5.3`-style values) and a fixed API endpoint reference
  (`v2` -> `v1`, matching what `score_image_inat.R` actually calls and this session
  confirmed live-working).
- Doc additions: camera-trap crop-filename `observation_id` collision behavior; iNat CV
  rate-limit note (60 req/min).

**Considered and declined (with reasoning):**
- The full architectural collapse into one generic `.read_classifier_output(files,
  parser_fn, ...)` engine Claude's embedded review proposed (estimated to cut the file
  from ~450 to ~225 lines): **not done.** These are three separately field-tested,
  live-production functions (all three exercised against real camera-trap/API data in
  earlier sessions per this file's own session history); a large structural rewrite
  chasing a stylistic win, without a live-testing budget to re-verify all three pathways
  afterward, is exactly the kind of premature abstraction this project's own conventions
  warn against. The additive helper consolidation above captures the safe, real DRY wins
  without that risk.
- `.resolve_image_files()`/`.path_folder_components()` in `score_image_inat.R` (the review
  raised this concern in both files) called "overly complex" / "seems like a simple
  existence test would suffice": kept as-is -- the base-directory/common-ancestor logic
  exists specifically to derive the `folder_1`, `folder_2`, ... metadata columns that the
  real `score_image_workflow.R` production script already keys off of
  (`FOLDER_TO_SPECIES`). Simplifying it would silently break that.
- SpeciesNet's "`top_n` adds little value since it typically returns one prediction per
  image" claim: not verified this session (no real SpeciesNet output available), so the
  documentation was not changed either way.

### `report_match.R`

**Fixed:**
- **Real doc/code contract bug:** `@param match_data` said "must contain... `score`," but
  the function only ever reads `score_original` (the actual canonical column name per this
  package's own standardization convention). Fixed the documentation to match the code
  (code was correct; doc was wrong).
- **Real bug:** the `verbose` parameter was declared and documented ("Print summary
  messages") but never referenced in the function body. Wired to a real summary
  `message()`.
- **Real correctness bug:** results text unconditionally appended `%g%%`, which would
  print e.g. `"Median top match score was 0.87%"` for a 0-1-scale acoustic/image
  confidence score. Fixed: `%` formatting now only applies when `data_type` is `"eDNA"` or
  `NULL` (the historical percent-identity default); `"image"`/`"acoustic"` report the raw
  score value unlabeled, since no single scale is safe to assume across classifiers
  (BirdNET/Animl are 0-1, iNaturalist CV is 0-100 -- confirmed live this session).
- `data_type` auto-detection logic and its eDNA-only scope now documented explicitly.
- `@return` now documents that `results` can be `NULL` and that `params` may contain
  pass-through fields from `attr(match_data, "report_params")`.
- Added a self-contained `@examples` block (no BLAST call required) alongside the existing
  `\dontrun{}` one.
- Added a citation (Altschul et al. 1990) when `method` indicates BLAST, closing the
  `citations = NULL` placeholder gap for the one case this function can reliably attribute.
- Methods text now adds a one-sentence clarification for `"image"`/`"acoustic"` data
  (ranked by classifier confidence, not percent identity).

**Considered and declined (with reasoning):**
- Richer statistics (proportion of observations above a threshold, score distribution):
  a real feature request, but a larger scope decision than a review-response pass should
  make unilaterally; not added.
- MIQE-eDNA reporting fields (`database_version`, `algorithm_version`) on
  `blast_sequences()`'s `report_params`: not implemented -- BLAST doesn't expose a
  reliable version signal without additional live NCBI calls out of scope here. Note that
  `report_match()`'s existing `params <- c(params, rp[!names(rp) %in% names(params)])`
  merge *already* passes through any such fields automatically the moment a future
  `blast_sequences()` enhancement supplies them -- no further change needed here when that
  happens.

### `score_image_inat.R`

**Fixed (2 real bugs found via live verification, see above):**
- **EXIF sign-flip bug:** `.extract_exif_info()` manually re-applied the S/W sign
  correction on top of `exifr`'s already-signed output, silently flipping every correct
  Southern-hemisphere latitude and Western-hemisphere longitude back to positive. Fixed by
  trusting `exifr`'s own sign and removing the redundant flip (with an inline comment
  citing the live verification that established this).
- **Rate-limit math error:** the review's embedded Claude comment claimed the existing
  `Sys.sleep(0.2)` (5 req/sec) was "5x more conservative than necessary" against a
  documented 60 req/min (~1 req/sec) limit -- backwards: 5 req/sec is 5x *over* the limit,
  not under it. Fixed to `Sys.sleep(1.0)` (skipping the trailing sleep after the last
  request, also addressing the review's separate cosmetic point about that).

**Also fixed:**
- `top_n` validation reordered (type-check before coercion), matching the fix applied
  identically in the other two ingest files.
- `has_coords <- has_lat && has_lng` introduced, replacing the `has_lat`-as-proxy-for-both
  pattern the review flagged as a latent confusion risk.
- EXIF extraction is now conditional (`need_exif`), skipping the `exiftool` call entirely
  when `lat`/`lng`/`observed_on` were all supplied directly -- previously called on every
  image regardless. A single upfront warning fires if `exifr` isn't installed and is
  actually needed, replacing what would otherwise be silent per-image degradation.
- The empty-result early return now uses a properly-typed 0-row tibble (matching the
  package's "empty but formatted" convention elsewhere) instead of a bare
  `tibble::tibble()`.
- EXIF date parsing broadened to also accept an already-ISO `"YYYY-MM-DD..."` string, not
  only the canonical EXIF `"YYYY:MM:DD..."` format.
- Genus extraction now uses the shared `.extract_genus()`; missing-file errors use
  `.stop_missing_files()`.
- Doc additions: `geo_prior_weight = NA` when `vision_score == 0`; `freq_score`'s
  presence-indicator caveat surfaced to `@return` (previously only in `@details`);
  `recursive` silently ignored for a file-vector `image_path`; a real `@examples` block
  (previously entirely absent, the review's flagged gap); a new biases/limitations section
  (geomodel training biases, camera-trap out-of-distribution caveat, recommending
  `read_animl_output()`/SpeciesNet as a camera-trap-native alternative); rate-limit
  documentation.

**Considered and declined (with reasoning):**
- `.resolve_image_files()`/`.path_folder_components()` complexity: see the matching entry
  under `read_image_classifiers.R` above -- same reasoning, needed for `folder_N`
  metadata.
- Merging `.parse_inat_cv_response()` (this file, live API) with `.parse_inat_cv_file()`
  (`read_image_classifiers.R`, saved JSON): declined -- their output schemas differ
  substantially (12 columns including `vision_score`/`combined_score`/`freq_score`/
  `geo_prior_weight`/`taxon_id`/`n_observations` vs. 7 simpler columns), and a shared
  parser would need a large optional-field surface for a marginal win.
- `httr` -> `httr2` migration: this file's `httr` code paths were just live-tested this
  session (real 200 responses, real JSON parsing) as part of verifying the two bugs above;
  rewriting to `httr2` without a matching live re-verification pass risks introducing a
  regression in a function that makes real external API calls, for a pure consistency
  benefit. Deferred to a dedicated session; `blast.R`'s own `httr2` usage is unaffected
  either way.

### `sequence_input.R`

**Fixed:**
- `.read_esv_dataframe(df, ...)` parameter renamed to `esv_df` (shadows `stats::df()`).
- `.parse_semicolon_headers()`'s `do.call(rbind, lapply(...))` growth pattern replaced with
  a pre-allocated character matrix filled row-by-row, closing the flagged O(n²) risk for
  FASTA files with many sequences.
- ASV-ID zero-padded-string generation (duplicated identically in three helpers) and the
  core 4-column output constructor (also duplicated in three helpers) consolidated into
  `.generate_asv_ids()` and `.build_core_seq_df()`.
- `.build_core_seq_df()` additionally now warns (not errors) on sequences containing
  non-IUPAC nucleotide characters and on duplicate sequences -- both real, previously
  entirely unchecked data-quality gaps the review flagged.
- `utils::globalVariables(c("abundance", "length"))` **removed** -- verified directly (not
  just trusting the review's suspicion) that neither name is referenced via NSE anywhere
  in this file; both are accessed only via `$`/`[[` indexing, which never triggers the
  R CMD CHECK note this declaration exists to suppress.
- `non_abundance_names` moved from a per-call local vector inside `.read_esv_dataframe()`
  to a module-level `.non_abundance_col_names` constant, easier to find/extend as new
  provider formats are added; only built when the auto-detect branch actually runs
  (unchanged from before -- it was already inside the relevant `if`/`else`, now just also
  hoisted out of the function body).
- `filter_sequences()`'s `len_range <- NULL` initialized before the `if (do_length)` block
  (was previously only assigned inside it, technically safe by construction but flagged as
  poor practice for a reader scanning forward).
- `filter_sequences()` now `message()`s explicitly when abundance filtering is skipped
  because no `abundance` column exists (was previously silent).
- `filter_sequences()` gained a `report_params` attribute (`min_length`, `max_length`,
  `min_abundance`, `n_retained`), mirroring `blast_sequences()`'s own, closing the gap the
  review flagged for a future `report_filter()`/`report_match()` integration.
- Abundance-column auto-detection now logs which column names were actually summed, not
  just the count.
- All internal helpers gained `@noRd` roxygen blocks (was `# --- Internal: ...` comments
  only, inconsistent with the rest of the package).
- Doc additions: `abundance_cols` auto-detection rule pointer; `taxonomy` argument's
  required join-column names spelled out explicitly (`"sequence"` vs `"accession"`);
  `@return`'s FASTA-path `accession` column documented; `sequence_col` case-sensitivity
  behavior noted; OTU-table (transposed) format limitation documented; length-filter-scope
  caveat (operates on `length`, not always re-derived from `sequence`) added; the
  Jonah-Ventures-specific example generalized to "provider ASV tables" with JV as one
  example.

**Declined:** `min_length`/`max_length` positive-integer validation duplicated in
`filter_sequences()` itself -- presumed already handled by
`TaxaTools::resolve_barcode_lengths()`, not independently verified this session; adding
redundant validation without confirmed evidence of a real gap wasn't done.

### `standardize_match_data.R`

**Fixed:**
- **Real CRAN-policy issue, the review's own stated top structural concern:**
  `.standard_match_ranks <- TaxaTools::extended_ranks` was a top-level assignment (runs at
  package attach time). Moved inside `.detect_rank_cols()`, evaluated only when the
  function actually runs.
- Three repeated validation patterns consolidated into shared helpers: `.check_col_exists()`
  (column-not-found stop pattern, 3 instances), `.check_rename_safe()` (rename-collision
  guard, 3 instances), `.validate_rank_system()` (rank_system type/length check, used in
  both `standardize_match_data()` and `filter_redundant_hypotheses()`).
- **Real robustness fix:** `data = NULL` now checks `interactive()` before calling
  `file.choose()`, raising a clear error in non-interactive contexts (Rmd/Quarto, batch
  scripts, CI) instead of hanging or erroring uninformatively.
- `col_map` gains a basic type/names validation before being passed to
  `TaxaTools::rename_cols()`.
- `.read_match_file()` now warns when the delimiter-inference result parses to a single
  column -- the most common symptom of a file whose extension doesn't match its actual
  delimiter.
- `filter_redundant_hypotheses()`: added a short pseudocode comment stating the redundancy
  invariant precisely; renumbered the step comments 1-8 (was 1-4, 4b, 5 -- the "4b" label
  signaled an after-the-fact insertion); added a `warning()` when *none* of `rank_system`
  matches a `match_df` column at all (previously a silent no-op, exactly the "relying on
  run order" risk the review flagged for the standardize-then-filter pipeline ordering
  contract); added a separate `warning()` when *some* (but not all) `rank_system` entries
  are missing from `match_df` (typo detection).
- `@return`/`@seealso` doc additions on `standardize_match_data()` (lowercase-applies-to-
  retained-columns-too note; cross-reference to `filter_redundant_hypotheses()` as the
  natural next step; `taxon_name_rank`'s eDNA-reporting relevance).
- `filter_redundant_hypotheses()` doc gained a `@note` making its practical BLAST
  species+genus motivation explicit, and clarified the NA-`taxon_name_rank` and
  same-rank-competing-candidate edge cases.

**Declined:** renaming the `data` parameter (shadows base R's `data()` function) -- unlike
the internal `df` renames applied freely elsewhere in this response (zero-risk, purely
local variables), `data` here is `standardize_match_data()`'s own public, already-shipped
parameter name, matching common R convention (`lm(data =)`, `ggplot(data =)`). Renaming it
would be a breaking signature change for every call site using `data = ...` as a named
argument.

**Already correct, no change needed:** the `core_map <- core_map[names(core_map) !=
unname(core_map)]` line already had an inline comment ("Drop identity renames to avoid
spurious rename_cols warnings") directly above it -- the review's ask was already
satisfied.

### `TaxaMatch-package.R`

**Fixed (the review's stated primary concern for this file -- real discoverability gap):**
- Added **Image input** and **Acoustic input** sections -- previously `read_birdnet_output()`,
  `read_animl_output()`, `read_inaturalist_cv_output()`, `read_wildlife_insights_output()`,
  and `score_image_inat()` were entirely absent from `?TaxaMatch`, meaning a user consulting
  the package index would see only BLAST/sequence functionality for a package whose stated
  scope explicitly includes acoustic and image classifier ingestion.
- Added `add_lowest_consistent_rank()` to the Standardization section (also missing from
  the index, independently confirmed in `taxonomy_consistency.R`'s own review comments).
- Broadened the package `@description` to mention backbone conversion (previously
  described only sequence/BLAST functionality despite `convert_taxonomy_backbone()` being
  a documented, prominent function).
- Added a `@section Workflow:` with the full call-order narrative (sequence and
  image/acoustic pathways), per the review's specific ask for a package-level pipeline
  overview.
- Converted `\itemize{\item \link{}}` to `\describe{\item{\link{}}{...}}`, matching the
  convention used in every function's own `@return` block elsewhere in this package.
- Added `@references` (BLAST, BirdNET, MegaDetector citations).
- Added `@seealso` pointing to TaxaLikely (the declared downstream consumer of this
  package's output).
- Confirmed every `\link{}` cross-reference resolves to a real exported function (checked
  directly against the current `R/` source, not assumed).

**Declined:** moving `convert_taxonomy_backbone()` to its own "Taxonomy" section -- the
review's own framing called this "a minor organizational judgment call rather than a
correctness issue"; left under Standardization. Package-wide dash-convention
standardization (`--` vs em-dash) -- out of scope for a single file's fix, would touch
every roxygen block across the whole package.

### `taxonomy_consistency.R`

**Fixed:**
- **The review's own stated highest-priority performance issue:** `add_lowest_consistent_rank()`'s
  `lapply(unique_ids, function(id) { idx <- which(obs_ids == id) ... })` re-scanned the
  full `obs_ids` vector for every unique observation (O(n x unique_obs)). Replaced with a
  precomputed `split(seq_len(nrow(match_obj)), obs_ids)` index built once, reducing this to
  O(n) -- exactly as the review recommended, and confirmed to preserve identical behavior
  for `NA` observation IDs (`split()` drops `NA` groups the same way
  `which(obs_ids == NA)` already always returned empty, since `NA == NA` is `NA`, not
  `TRUE`).
- The `rank_system` auto-detection block (duplicating `standardize_match_data.R`'s
  `.detect_rank_cols()` logic almost verbatim) now calls `.detect_rank_cols()` directly --
  it's a plain internal function, already visible package-wide, so no promotion to a
  shared file was needed, just removing the duplicate implementation.
- Three redundant `names(x) <- unique_ids` assignments removed -- `vapply()` over the
  already-named `per_obs_list` already returns a correspondingly-named vector.
- `majority_threshold <= 0.5` now issues a `warning()` (was previously silently accepted
  despite the doc's own "semantically unusual" caveat).
- Inline comments added at the `__MISSING__`-sentinel-revert line and the
  `max(which(consistent))` finest-rank idiom, both specifically requested.
- A `warning()` now fires when some (not all) of `rank_system` doesn't match a
  `match_obj` column (typo detection), matching the equivalent fix in
  `standardize_match_data.R`.
- Doc additions: single-candidate-observation and blank-rank-propagation edge cases (both
  can produce a falsely "fully resolved" `lowest_consistent_rank`); the `"__MISSING__"`
  sentinel-collision caveat; explicit note that all original `match_obj` columns are
  retained unchanged.

**Already correct, no change needed:** `rank_majority_fraction`'s "computed over non-blank
candidates, not all candidates" behavior was already explicitly stated in `@return` --
the review's ask here was already satisfied in the current code.

**Declined:** extracting the `.get_vals()` closure to a standalone package-level function
for independent testability -- a legitimate closure-over-`na_as_inconsistent` pattern
already (correct, not a bug); the marginal testability benefit didn't seem worth touching
working code with no verified defect.

------------------------------------------------------------------------

## Summary

| Category | Count |
|---|---|
| Real bugs found and fixed (confirmed via live external-service verification or direct code tracing) | 5 (EXIF sign double-flip, rate-limit math error, `report_match()`'s `%`-formatting bug, `report_match()`'s unused `verbose`, `.warn_duplicate_basenames()`'s own false-positive found mid-session) |
| CRAN-policy / correctness issues fixed | 2 (`.standard_match_ranks` top-level side effect; `convert_taxonomy_backbone()`'s missing `clean_taxon_names()` pass on extracted rank values) |
| New shared internal helpers (DRY consolidation) | 8, in new `R/utils_shared.R` |
| Files renamed to match their exported function(s) | 3 |
| Items explicitly declined, with reasoning recorded above | ~15 |

All fixes verified against the full test suite and `R CMD check` after every file, not
just once at the end; the two live-verification questions were resolved with real external
calls (iNaturalist CV API, `exiftool`) rather than assumed from documentation alone.

------------------------------------------------------------------------

------------------------------------------------------------------------

## Functions added or modified since this review (through 2026-09-07)

The functions below were added or modified after this review's own date
(above), in response to client requests and/or fixes identified during
testing against real production data, consistent with USGS code review
policy. Each was individually code-reviewed against the same checklist
used above (functionality, coding standards, vulnerabilities, and -- where
applicable -- domain/scientific reasonableness) as part of this software
release.

- `.accession_review_fingerprint`
- `.align_to_cache_columns`
- `.apply_local_veto`
- `.apply_top_n`
- `.attach_taxonomy`
- `.blast_against_comparison_set`
- `.blast_local`
- `.blast_poll`
- `.blast_rate_limit_sleep`
- `.blast_remote`
- `.blast_server_rejected`
- `.blast_submit`
- `.build_accession_review_prompt`
- `.build_core_seq_df`
- `.build_params_key`
- `.build_submission_batch_lookup`
- `.check_col_exists`
- `.check_pkg`
- `.check_rename_safe`
- `.compute_hierarchy_congruence`
- `.default_params_key`
- `.detect_rank_cols`
- `.empty_acc_taxonomy_result`
- `.empty_animl_result`
- `.empty_birdnet_result`
- `.empty_blast_result`
- `.empty_inat_result`
- `.empty_raw_hits`
- `.empty_reference_pair_cache`
- `.empty_speciesnet_result`
- `.evaluate_reference_accessions_chunk`
- `.extract_amplicon_one_tm`
- `.extract_exif_info`
- `.extract_feature_table_fallback`
- `.extract_genus`
- `.fetch_marker_annotation`
- `.fetch_reference_accession_records`
- `.filter_and_cap_accessions`
- `.filter_blast_hits`
- `.fmt_time`
- `.generate_asv_ids`
- `.get_species_comparison_meta`
- `.investigate_flagged_accession_core`
- `.investigate_params_key`
- `.investigate_verdict`
- `.join_taxonomy`
- `.label_confidence_from_evidence`
- `.load_accession_review_cache`
- `.load_investigate_cache`
- `.load_reference_accession_cache`
- `.load_reference_pair_cache`
- `.local_corroboration_columns`
- `.lookup_investigate_cache`
- `.na_like`
- `.parse_accession_review_response`
- `.parse_animl_file`
- `.parse_birdnet_df`
- `.parse_birdnet_file`
- `.parse_blast_xml`
- `.parse_create_date`
- `.parse_inat_cv_file`
- `.parse_inat_cv_response`
- `.parse_lat_lon`
- `.parse_semicolon_headers`
- `.parse_speciesnet_label`
- `.parse_speciesnet_predictions`
- `.parse_taxonomy_xml`
- `.partner_trust_weight`
- `.pivot_wide_animl`
- `.print_investigation_summary`
- `.read_dada2_matrix`
- `.read_dna_stringset`
- `.read_esv_dataframe`
- `.read_fasta_file`
- `.read_match_file`
- `.recover_truncated_accession_json`
- `.reference_action_from_confidence`
- `.resolve_expected_marker`
- `.resolve_image_files`
- `.resolve_label_params`
- `.resolve_locations_by_acc`
- `.resolve_marker_pattern`
- `.resolve_taxonomy`
- `.resolve_taxonomy_by_acc`
- `.resolve_trimmed_span_max`
- `.review_accession_batch_with_retry`
- `.same_submission_batch`
- `.save_accession_review_cache`
- `.save_investigate_cache`
- `.save_reference_accession_cache`
- `.save_reference_pair_cache`
- `.search_species_accessions`
- `.speciesnet_detection_coverage`
- `.split_batches_by_length`
- `.stop_missing_files`
- `.store_investigate_result`
- `.strip_acc_version`
- `.summarise_corroborators`
- `.trim_queries_to_amplicon`
- `.valid_reference_length`
- `.validate_min_conf_top_n`
- `.validate_rank_system`
- `.warn_duplicate_basenames`
- `.warn_na_coercion`
- `add_lowest_consistent_rank`
- `blast_sequences`
- `check_marker_mismatch`
- `convert_taxonomy_backbone`
- `corroborate_references_locally`
- `evaluate_reference_accessions`
- `filter_redundant_hypotheses`
- `filter_sequences`
- `flag_incongruent_references`
- `investigate_flagged_accession`
- `investigate_flagged_accessions`
- `match_driving_accessions`
- `migrate_reference_cache`
- `read_animl_output`
- `read_birdnet_output`
- `read_inaturalist_cv_output`
- `read_sequence_table`
- `read_speciesnet_output`
- `refine_reference_verdicts`
- `remove_incongruent_references`
- `report_match`
- `resolve_review_overrides`
- `review_flagged_accessions`
- `score_image_inat`
- `score_reference_labels`
- `standardize_match_data`
- `verify_flagged_references`
- `verify_local_corroborations`
- `verify_removal_candidates`

