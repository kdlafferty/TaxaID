# CLAUDE.md -- TaxaFetch
# Last updated: 2026-09-05 (Opus 5 -- GBIF fetch: integrity, non-blocking communication,
# candidate scoping, and zip retention. Four separate real failures from one overnight
# PtConception 18S run, in the order they bit:
#
# (1) TRUNCATED DOWNLOAD CACHED AS COMPLETE. 127,733,417 of GBIF's declared 130,577,434
# bytes; a zip's central directory is at the END, so the file still passed file.exists()
# and even `file`'s magic-byte check, then failed in unzip() on EVERY re-run -- a
# self-perpetuating poisoned cache with no hint the cache was at fault. NEW
# .gbif_zip_intact()/.gbif_declared_size(): verify-before-cache with one retry, metadata
# written ONLY after verification, verify-on-cache-hit with a self-healing re-fetch of the
# same prepared key. .read_gbif_zip() also promotes unzip's extraction WARNING to an error
# (a corrupt payload otherwise yields a silently SHORT occurrence table). The cache-size
# report is wrapped: a cosmetic step must never discard 1.7M imported rows, which it did.
#
# (2) menu() ATE THE ENTIRE WORKFLOW. utils::menu() reads stdin, and RStudio queues the
# rest of a sourced script as console input -- so the prompt consumed ~600 script lines as
# answers, re-prompting on each and SILENTLY SWALLOWING them so they never ran. The GBIF
# download had succeeded; everything after it just did not happen. interactive() is TRUE
# whether a human is typing or the editor is pumping lines, so it cannot gate this. NEW
# allow_prompts = FALSE (default): nothing blocks; every decision is REPORTED with the
# command to act on it. This package already documented the same hazard for readline() in
# TaxaMatch::group_observations_by_bbox(), whose advice ("run this call on its own") is
# unavailable to a function called mid-workflow. NEVER add a blocking prompt here.
#
# (3) OUTLIER CHECK SWEPT A FAMILY-DERIVED POOL. check_geographic_outliers() fetched global
# GBIF data for EVERY locally-rare species, one HTTP request per key, and earned an outright
# rate-limit block at ~360/829 ("Too many requests! ... please use occ_download()"). Only
# 387 of 7,392 pool species (5.2%) are match candidates and only 613 of 3,133 genera contain
# one -- 95% of the requests protected against a harm those species cannot cause, since a
# species with 1-4 local records sits far below join_priors()'s expansion_min_prior and can
# never become a hypothesis. NEW candidate_taxa/candidate_scope ("genus" default keeps
# congeners, which restore_suppressed_candidates()/expand_unreferenced_hypotheses() CAN
# promote; "all" restores the old sweep). Real reduction: 2,683 -> 591. Also routed through
# get_gbif_occurrences() for the backend switch, and NEW verdict caching -- the global cloud
# collapses to one integer per species plus one logical per local record, so caching the raw
# cloud stored millions of records to preserve a few thousand numbers. NOTE rank_filter is
# passed as NULL, NOT the wrapper's "species" default: that would have changed which records
# qualify while only the BACKEND was meant to change (caught by pre-existing tests).
#
# (4) THE ZIPS ARE THE CACHE. 38 zips = 17.0 GB; every .rds checkpoint together = 52 MB. A
# zip is pure redundancy once imported. NEW keep_zip (delete after a SUCCESSFUL import,
# metadata KEPT so the download key stays re-fetchable with no new request) and NEW
# taxafetch_clear_cache(zips_only = TRUE) for existing accumulation -- unlike orphans_only
# (which finds zero here) it includes zips current metadata still points at, which are
# exactly the 2 GB ones. Defaults unchanged: keep_zip = TRUE.
#
# DELIBERATELY NOT BUILT: a GBIF density-tile pre-screen. The tiles are alpha-channel
# presence/absence only ("not a decoded density value"), cc_outl() needs real coordinates,
# and a pre-screen's job is to SKIP the real test -- an unvalidated skip risks false
# negatives on exactly the misidentifications this check exists to catch. Candidate scoping
# already removed the bottleneck.
#
# devtools::test() 737 pass / 2 fail (both pre-existing filter_gbif_quality/
# CoordinateCleaner environment failures, unrelated).
#
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-09-04 (Sonnet 5, branch cache-management -- the user reported
# ~/Library/Caches/org.R-project.R/R/TaxaFetch at 23GB (89 files) and asked for an
# investigation before deciding on a fix. Root cause: download_gbif_occurrences()'s
# GBIF-download zip cache has no expiration and, on `overwrite = TRUE`, silently
# ORPHANED the previous zip -- it repointed the query's metadata file at the fresh
# download without ever deleting the stale one, so every re-run of the same query
# with overwrite=TRUE left a dead multi-GB zip behind. Fixed: `overwrite = TRUE`
# now shows the cached zip's date/size and asks (via `utils::menu()`) whether to
# overwrite or keep it in an interactive session; a non-interactive session
# proceeds straight to a fresh download as before, but either way the stale zip is
# now deleted once the new one lands -- never left as an orphan. Live-verified via
# a real GBIF download in `inst/test_overwrite_cache_manual.R` (a throwaway manual
# test script, not part of the automated suite): confirmed the old zip is removed
# on "Overwrite" and untouched on "Keep."
#
# NEW `taxafetch_clear_cache(cache_dir=, older_than_days=, orphans_only=, dry_run=)`
# reports/clears the cache -- `orphans_only = TRUE` targets ONLY zips no longer
# referenced by any current `download_gbif_occurrences()` metadata file (i.e. the
# exact pre-fix leftovers), leaving the current zip for every distinct query
# untouched. `download_gbif_occurrences()` also now prints a cache-size summary
# after every run and offers to clear it once the cache passes 1GB. Live dry-run on
# the user's real 23GB cache found 13 orphaned zips / 6.3GB; user confirmed and
# cleared them, bringing the cache to 17GB (76 files) -- the remainder is genuinely
# distinct per-query downloads, not further orphans.
#
# A full ecosystem audit (all 9 packages) for the SAME cache-accumulation pattern
# found one more real instance (TaxaLikely's `fetch_ncbi_reference_sequences()`/
# `audit_barcode_coverage()` cache -- see TaxaLikely/CLAUDE.md's own note) and
# confirmed TaxaMatch's reference-evaluation caches are a DIFFERENTLY-SHAPED,
# CUMULATIVE cache (one consolidated file, row-level TTL, "congruent" verdicts
# cached forever by design) that must NOT get this same file-deletion treatment --
# deliberately left untouched, see TaxaMatch's own cache design (asymmetric TTL +
# `migrate_reference_cache()`), already correct.
#
# `taxafetch_clear_cache()` itself was then refactored (still this session) onto a
# new shared engine in TaxaTools (`list_cache_files()`/`report_and_clear_cache()`,
# see TaxaTools/CLAUDE.md's own note) -- also used by TaxaLikely's new
# `taxalikely_clear_cache()`. Only the orphan-detection logic (reading each zip's
# meta.rds to tell "current" from "superseded") stayed local, since it has no
# TaxaLikely analog. `.taxafetch_cache_patterns` also gained `openalex_cache_*.rds`
# (found during the audit: `search_literature()`'s OpenAlex cache is the same file
# shape but wasn't previously recognized by this function's pattern list -- dormant
# on this machine, cache_dir defaults to NULL/disabled, but would silently survive
# a clear if ever pointed at a shared cache_dir).
#
# README gained a "Cache" section. `devtools::test()` 676/676 (0 failures; 2
# pre-existing unrelated CoordinateCleaner/terra environment failures untouched),
# `devtools::check()` 0/0/0, reinstalled and verified at `~/Library/R/4.0/library`.
# Previous update, 2026-08-28 (Fable 5, branch undetected-evidence-mixture --
# check_inat_range() output gains a `name_match` column (mixture redesign D6
# prerequisite; closes [[project_inat_range_backbone_mismatch_todo]]): iNat's
# taxon search takes the single best TEXT match, so a query can silently resolve
# to a DIFFERENT species (real case: Gasterosteus gymnurus -> G. aculeatus with
# in_range = TRUE for the wrong organism). name_match is DERIVED AT ASSEMBLY TIME
# from taxon_name/matched_name -- never cached -- so previously cached rows get
# it too; consumers that elevate priors on an in_range verdict now gate on it
# (TaxaExpect::generate_inat_range_evidence(), TaxaAssign::
# adjust_inat_range_priors(require_name_match = TRUE)). 1 new offline test + the
# nine-columns schema test updated to ten. devtools::test() 620 passed / 2
# pre-existing unrelated CoordinateCleaner/terra environment failures, check()
# 0/0/0, reinstalled.
# Previous update, 2026-08-20, continued (Sonnet 5 -- fetch_nas_occurrences()/lookup_huc8()
# REMOVED, same day they were added (see the entry directly below for the original build).
# The user corrected the architecture directly: TaxaID is meant to stay a generic, taxon-
# and geography-agnostic toolkit, and baking a narrow (aquatic-only, US-only) external
# database plus freshwater-specific watershed-connectivity math into a package function ties
# the whole ecosystem to one client's one study system. The distinguishing principle from
# what's already shipped: iNat/GBIF calls (e.g. TaxaFetch::fetch_inat_occurrences(), already
# used by TaxaExpect::generate_domestic_food_priors()) are fine because they're broad, generic
# infrastructure used across many studies; a single-country single-taxon-group database, and
# HUC8 watershed math, are not. Both functions deleted entirely (source, tests, man/ pages,
# NAMESPACE exports) -- no deprecation shim, since neither had any real caller yet (added and
# removed same session). devtools::test() 619/619 (down from 671, exactly the 52 tests removed
# with the two files; same 2 pre-existing, unrelated filter_gbif_quality()/CoordinateCleaner
# environment failures as before), devtools::check() 0/0/0. Reinstalled.
#
# The replacement design (TaxaExpect::apply_undetected_evidence(), built the same day) moves
# region-scoping and list-curation entirely to the caller's own workflow -- e.g. hand-pull a
# species list from NAS yourself, restricted to your own study region, and pass it in as a
# plain character vector. See TaxaExpect/CLAUDE.md's matching session note for the full
# redesign, including a cross-session design negotiation with a concurrent chat building a
# companion regional-proximity mechanism (ecosystem_docs/REENTRY_PROMPT_
# regional_proximity_prior_check.md) that converged on a shared "evidence generator + one
# shared applier" architecture both mechanisms now use.
# Previous update, 2026-08-20 (Sonnet 5 -- initiates ecosystem_docs/REENTRY_PROMPT_
# invasive_species_watch_list_priors.md: TaxaFetch gains fetch_nas_occurrences() (new,
# R/fetch_nas_occurrences.R) and lookup_huc8() (new, R/lookup_huc8.R), the acquisition side
# of an invasive/nonindigenous-species watch-list prior mechanism (consumer:
# TaxaExpect::generate_invasive_watch_priors(), see that package's own CLAUDE.md).
# fetch_nas_occurrences() queries the USGS Nonindigenous Aquatic Species (NAS) database's
# real, live v2 API (nas.er.usgs.gov/api/v2) -- confirmed this session, not assumed from the
# reentry doc's own design question 1 ("check whether NAS has a queryable API before
# committing to a design"): a real JSON API exists, needs no API key for the
# /species (full 1,515-species catalog) and /occurrence/search?species_id= endpoints used
# here, and a plain httr::GET() with R's default user-agent works fine (only a bare curl
# request without a browser-spoofed UA hit Cloudflare's bot-check page -- httr's own UA
# apparently doesn't trip it). Critically, NAS's per-occurrence-record `status` field
# (established/stocked/collected/failed/unknown) gives a real, ready-made tiering signal the
# reentry doc's own design question 2 asked for, and huc8/huc10/huc12 codes come free on
# every record, answering design question 3 (regional scoping) without needing a separate
# Watershed Boundary Dataset join for the NAS side. lookup_huc8() resolves a study's own
# lat/lon to its HUC8 via a second live, no-key USGS service (hydro.nationalmap.gov's WBD
# ArcGIS MapServer, layer 4 = 8-digit HU/Subbasin -- confirmed via that service's own layer
# list, not guessed) -- so a caller never has to hand-look-up a HUC8 code.
#
# A real, load-bearing finding from checking the API before building anything (per the
# reentry doc's own explicit instruction): NAS is United States-only, and does NOT contain
# the Alburnus alburnus/Nova Scotia record that originally motivated this whole design --
# confirmed by pulling NAS's full species catalog and finding zero Alburnus entries at all.
# Cross-checked via a live GLOBAL (non-bbox-restricted) GBIF query: the Nova Scotia
# detections DO exist (133 real 2019-2021 Canadian records), but every one is a
# MATERIAL_SAMPLE eDNA metabarcoding record, not a vouchered specimen, with no
# established-population signal of any kind. Presented this finding to the user directly
# before proceeding (AskUserQuestion) rather than silently building around it or silently
# extending scope to cover it -- user chose "NAS only, for now," explicitly accepting the
# Alburnus-style foreign-detection gap as a known, documented limitation rather than solving
# it this session (a global-GBIF-fallback channel was offered and declined). Both
# fetch_nas_occurrences()'s own roxygen (`@section Scope`) and
# TaxaExpect::generate_invasive_watch_priors()'s roxygen state this limitation explicitly,
# with the real Alburnus case as the concrete example.
#
# Live-verified end to end before considering this done (not just devtools::test()/check()):
# lookup_huc8(41.6, -87.15) (a real BurnsHarbor-area Lake Michigan point) correctly resolves
# to "04040001"/"Little Calumet-Galien"; fetch_nas_occurrences() against three real species
# (Ictalurus furcatus, Alburnus alburnus, Gymnocephalus cernua) correctly returns "ok" with
# 5,092+ real occurrence rows for the two NAS-tracked species and "not_in_nas" for Alburnus;
# and a full generate_invasive_watch_priors() run against that real HUC8 correctly reports
# Gymnocephalus cernua (Ruffe, a real, famous Great Lakes invader) as
# "nonindigenous_watch" rather than "nonindigenous_established" -- NAS's own establishment
# records for Ruffe are concentrated in the Lake Superior/Duluth-Superior basin, a DIFFERENT
# HUC8 than this southern-Lake-Michigan test point, so the tiering mechanism correctly
# distinguishes "established somewhere in the US" from "established in THIS region" rather
# than over-crediting a real invader for the wrong watershed -- a genuine, non-trivial
# correctness demonstration, not a coincidence of the test data.
#
# devtools::test() 671/671 (up from 646 -- 25 new tests across
# test-fetch_nas_occurrences.R/test-lookup_huc8.R; 2 pre-existing, unrelated failures in
# test-filter_gbif_quality.R, the documented CoordinateCleaner/terra/sf environment-version
# issue from the 2026-08-08 note below, confirmed unrelated -- neither new file touches
# CoordinateCleaner or filter_gbif_quality.R). devtools::check() 0 errors/0 warnings/1 note
# (pre-existing "unable to verify current time" clock artifact). Reinstalled to
# ~/Library/R/4.0/library. No new package dependency -- httr/dplyr/tibble were already
# Imports. See TaxaExpect/CLAUDE.md's matching note for the consumer side, and the reentry
# doc itself for the full design record, including the two still-open design questions this
# session's own findings partially answer (tiering ESS magnitudes are a first-pass heuristic,
# not yet empirically calibrated; whether this mechanism should share machinery with the
# companion REENTRY_PROMPT_regional_proximity_prior_check.md doc remains undecided, per that
# doc's own "prototype one first" guidance -- this session prototyped the invasive-watch
# side only).
# Previous update, 2026-08-08 (Sonnet 5 -- first human-authored code + domain review response.
# The user replaced the old Claude-authored inst/taxafetch_review.Rmd (Session 148) with a
# fresh human-authored review by Micah Wright, covering the same 24-file structure. Full
# record in inst/taxafetch_review_response.md. Real bugs found and fixed, all confirmed via
# direct testing before shipping (not just reading the diff): (1) search_dataone()'s
# coordinate parsing never matched PASTA's real spatialCoverage/coordinates XML structure or
# its Solr ENVELOPE(minX,maxX,maxY,minY) string -- coordinates_raw was NA for every real
# record; the reviewer's own live example (a real SBC LTER Kelp Forest dataset) reproduced
# it exactly. (2) dataone_catalog.R's authors/keywords_str columns came back NA for every
# real record -- XPath now tries several real candidate node shapes instead of one guessed
# shape. (3) dataone_standardize.R's .extract_eml_sites() site-code regex silently failed on
# any geographicDescription containing an embedded newline (missing PCRE (?s) flag) -- same
# documented footgun class as this file's own Known Footguns entry, reproduced with the
# reviewer's real "ABUR: Arroyo Burro Reef..." example. (4) fetch_gbif_occurrences(
# year_range = NULL) crashed with cache_dir enabled ("argument is of length zero" inside
# .gbif_checkpoint_path()) -- a real, reachable path via TaxaExpect::build_priors()'s own
# year_range=NULL default forwarding straight through; confirmed via a standalone
# reproduction before fixing. (5) A shared hardcoded year_range default ("2000,2024",
# identical across FIVE functions: fetch_gbif_occurrences/download_gbif_occurrences/
# get_gbif_occurrences/check_geographic_outliers/fetch_occurrences_by_taxon) was already
# silently excluding all 2025+ GBIF data for any default-argument caller by the time of this
# review -- fixed with a new .gbif_default_year_range() computed at call time, not a fixed
# literal. (6) filter_gbif_quality()'s basisOfRecord filter compared exact case/whitespace,
# inconsistent with the occurrenceStatus filter's own normalization (real inconsistency, low
# practical risk against real GBIF data but fixed for defense-in-depth). (7) pdf_extract.R:
# TaxaTools's %||% (deliberately NULL-only, used ecosystem-wide) was being applied to four
# screen_pdf_structure() axis fields that explicitly return NA_character_ (not NULL) on LLM
# characterization failure -- confirmed via a real bundled PDF where every one of these
# fields came back NA and stayed NA through prompt building, exactly as the reviewer found.
# New .axis_or_default() helper (NULL-or-NA-safe), 5 call sites fixed; %||% itself untouched
# (its NULL-only semantics are relied on elsewhere). (8) pdf_text.R's .match_header() Pass 2
# (two-column-layout header detection) never matched a NUMBERED header ("2.1 RESULTS ...")
# since it tested "^[A-Z]" against the raw line without first stripping the leading number
# the way Pass 1 already does -- fixed by applying the same strip. (9) pdf_api.R's
# build_pdf_extract_prompt() @examples used entirely wrong parameter names (pdf_meta/
# taxon_scope/bbox, none of which exist on the real function) -- fixed to match the real
# signature. Also fixed: a stale "TaxaExpect --" header banner (pre-Session-19-split doc
# drift) in 7 files, corrected to "TaxaFetch --"; pdf_api.R's file header and this file's own
# Function Inventory table both still claimed call_api_pdf() was "Anthropic-only" -- stale,
# predating Session 87's provider generalization (the function body itself already
# dispatched through TaxaTools::call_api(), only the docs were wrong); real df-shadows-
# stats::df() local-variable violations fixed in dataone_taxon_screening.R and
# pdf_extract.R (matching this ecosystem's established df -> input_df convention); several
# genuine DRY duplications consolidated (.detect_lat_col/.detect_lon_col/.detect_species_col
# in dataone_eml_screen.R; .pdf_dwc_cols vs. dataone_standardize.R's identical local
# dwc_cols; pdf_api.R's duplicated subprocess/in-process PDF-rendering logic, the latter
# verified end-to-end via callr both before and after to confirm the refactor didn't change
# behavior under subprocess serialization). Several other review comments were investigated
# and found to be either already-correct design (e.g. max_coord_decimal_places already
# defaults NULL; the literature_search.R bbox-is-metadata-only design is already documented;
# .coerce_numeric_col()/.coerce_integer_col() do add real column-specific warning value over
# bare as.numeric()/as.integer()) or genuine but out-of-scope architecture questions flagged
# for a future session rather than fixed unilaterally (data.frame vs. tibble consistency
# ecosystem-wide; EDIutils adoption; httr vs. httr2 consistency; three separate
# .bbox_overlaps()-style implementations across dataone_eml_screen.R/dataone_geo_screening.R/
# dataone_occurrence_search.R; inconsistent bbox-argument conventions across this package's
# own functions, list-only in search_dataone() vs. list-or-vector elsewhere) -- see the
# response doc for the full file-by-file record, including which of the reviewer's own
# suggested fixes were checked and found to be incorrect before being rejected (e.g. a
# one-liner gsub() simplification in pdf_extract.R that would have left a stray tag-word
# artifact; an is.null() check in download_gbif_occurrences.R that would have silently
# broken the empty-select_cols-intersection edge case). New test coverage for 3 previously-
# untested files (test-dataone_occurrence_search.R, test-pdf_text.R, test-pdf_extract.R).
# devtools::document() 0 errors (also fixed 4 pre-existing multi-line @importFrom blocks
# that a newer roxygen2 in this environment now rejects -- found blocking document(),
# unrelated to any review comment). devtools::test() 616/618 (2 pre-existing failures,
# confirmed via git stash to be present and identical before this session -- a
# CoordinateCleaner/terra/sf environment version issue, not caused by or related to any fix
# here), up from 565/565. devtools::check() 0 errors/0 warnings/0 notes. Reinstalled to
# ~/Library/R/4.0/library, confirmed via find.package(). See inst/taxafetch_review_response.md
# for the complete comment-by-comment record.
# Previous update, 2026-07-27 (Sonnet 5 -- geographic-outlier/institution-flag thread CLOSED OUT.
# Final live-testing bug, found by the user re-running MuguFishWorkflow.R (OUT_PREFIX =
# "MuguWilderFish_blast"): gbif_occurrences$institution_flag came back NULL, not just FALSE.
# Not a package bug -- the workflow script's own `if (file.exists(geo_outlier_path)) {
# gbif_occurrences <- readRDS(...) }` checkpoint branch was silently loading a stale
# MuguWilderFish_blast_geo_outlier_check.rds (dated 2026-07-23 15:42, predating
# institution_flag's existence on filter_gbif_quality()'s output), overwriting the correct,
# freshly-computed object from moments earlier in the same run. Same general "workflow
# checkpoint can go stale relative to updated package code" class of bug this ecosystem has
# hit before -- not fixable in the package itself. Fix: delete the one stale .rds, re-run.
# User confirmed afterward: "institution flag seems to be operating well." Closing
# verification pass: devtools::test() 565/565 (0 failures), devtools::check() 0 errors/0
# warnings/0 notes, no non-ASCII characters in any of the five new/modified source files
# across TaxaFetch+TaxaHabitat. No other unresolved issues from this thread. See
# [[project_geographic_outlier_check]] for the full record. Previous update, 2026-07-24
# (Sonnet 5 -- fetch_inat_occurrences() gains inat_kingdom
# (derived from iNaturalist's own iconic_taxon_name via the same .iconic_to_kingdom()
# lookup check_inat_range() already uses). Prompted by the user asking directly whether
# iNaturalist's own taxonomic backbone (distinct from both NCBI and GBIF) could cause a
# name search to resolve to the wrong organism -- confirmed real: iNat's /v1/taxa search
# takes the single best text match, so a homonym across kingdoms is possible, if rare
# (check_inat_range() already guards against exactly this for its own use case, but
# fetch_inat_occurrences() didn't expose the signal needed to do the same). Consumed by
# TaxaExpect::generate_domestic_food_priors()'s new kingdom cross-check (see that
# package's CLAUDE.md) -- a caller can now compare a candidate's own known kingdom
# against what iNaturalist actually resolved to before trusting the result. Purely
# additive (new column, no signature change). devtools::test() 0 failures (541, up from
# 539), devtools::check() 0/0/0. Reinstalled to ~/Library/R/4.0/library.
# Previous update, 2026-07-23, same day, yet another follow-up (Sonnet 5 -- dedupe_occurrences()
# split out of stack_occurrences() entirely, new file R/dedupe_occurrences.R. Prompted by the
# user's naming/design critique right after collapse_duplicate_occasions shipped: the name
# "stack_occurrences" implies pure row-combination, and bundling dedup logic inside a function
# named "stack" creates a real risk that a caller with only ONE data source reads the name,
# concludes stacking doesn't apply to them, and skips deduplication entirely -- exactly the
# documented GBIF-only pipeline pattern (get_gbif_occurrences() -> filter_gbif_quality(), no
# stack_occurrences() call at all). Confirmed this isn't hypothetical or new: the pre-existing
# gbifID dedup (Session 140) has the IDENTICAL blind spot (a single fetch_gbif_occurrences()
# call querying overlapping taxon keys can already produce duplicate gbifIDs within one
# un-stacked frame) -- so both mechanisms moved, not just the new one, per the user's explicit
# choice. stack_occurrences() now only combines frames + adds point_id (row count is always
# exactly the sum of inputs); dedupe_occurrences(data, ...) takes a single frame (stacked or
# not) and runs both checks. Every real call site across the monorepo found via grep and
# updated to add an explicit dedupe_occurrences() call: TaxaExpect::build_priors() (package
# code, runs unconditionally regardless of whether supplemental_occurrences was stacked),
# TaxaAssign/TaxaExpect/TaxaFetch inst/ workflow scripts (6 files), the root
# inst/TaxaID_Workflow_Template_TEST.R, the data-acquisition.Rmd vignette, and
# review_function_inputs.R -- all now call dedupe_occurrences() explicitly, including every
# single-source case, closing the exact blind spot this change exists to fix. Pipeline
# diagrams and Function Inventory below updated to match. devtools::test() 0 failures (563, up
# from 553 -- test-stack_occurrences.R's dedup tests moved+adapted into new
# test-dedupe_occurrences.R, 24 tests there), devtools::check() 0 errors/0 warnings/0 notes.
# See this file's Session Notes for the full record.
# Previous update, 2026-07-23, continued yet further (Sonnet 5 -- stack_occurrences() gains
# collapse_duplicate_occasions (default TRUE), prompted by a user design discussion starting
# from "does anything dedup redundant occurrence records" and landing on a real, concrete
# scenario: a rare-bird alert drawing dozens of independent eBird checklists for one
# individual, or a bioblitz producing a dozen independent iNaturalist uploads of one local
# population -- each a genuinely distinct GBIF record (so the existing gbifID step, Session
# 140, can't touch them) but not a distinct detection OCCASION. Verified before building --
# not assumed -- that this actually matters to a real downstream consumer:
# TaxaExpect::prepare_model_dataframe() counts raw records (dplyr::n()) as both n_species (the
# binomial numerator) and n_total_at_site (the shared effort denominator), so uncollapsed
# repeat reports of one individual inflate that species' modeled relative detection frequency
# directly, not just its raw record count. New params taxon_col ("scientificName")/date_col
# ("eventDate", falls back to year/month/day when absent -- needed since get_gbif_occurrences()'s
# "standard" columns carry year/month/day but not eventDate itself)/coord_precision (3 d.p.,
# reusing the same key formula fetch_dataone_occurrences() used to use for its own GBIF-snapshot
# dedup -- see below, that mechanism was removed the same session as now-redundant). Content-based
# match, not exact-ID -- a row missing any key component is always kept, never dropped on
# incomplete information; silent no-op when taxon_col/date_col aren't present at all, matching the
# gbifID step's own established convention (no new-column-missing message spam). Default TRUE, not
# opt-in, because this IS the correct occupancy-modeling semantics for what TaxaExpect actually
# consumes -- "was the species documented here, on this occasion" not "how many people documented
# it" -- confirmed with the user before defaulting it on rather than assumed. 9 new tests in
# test-stack_occurrences.R (collapse across different platforms/case-insensitive taxon match,
# distinct-date/species/location never collapsed, missing-key-component rows always kept,
# year/month/day fallback, opt-out via collapse_duplicate_occasions = FALSE, silent no-op with no
# taxon/date columns, custom taxon_col/date_col). devtools::test() 0 failures (549, up from 539),
# devtools::check() 0 errors/0 warnings/1 note (pre-existing clock-check NOTE).
# SAME DAY, immediate follow-up: the user asked whether this new step makes any EXISTING dedup
# redundant. Answer, worked through explicitly: the gbifID step is NOT redundant (it catches an
# exact-duplicate GBIF record with NA scientificName/eventDate, which collapse_duplicate_occasions
# deliberately never touches) -- but fetch_dataone_occurrences(gbif_snapshot_path=)'s own
# GBIF-snapshot dedup (.load_gbif_hashes()/.deduplicate_against_gbif(), same key formula) IS
# redundant for the realistic combined pipeline (fetch GBIF + fetch DataONE + stack_occurrences()),
# and actually less safe (it coalesced missing name/date/lat/lon to ""/0 before hashing, so two
# incomplete records could spuriously match, the opposite of the new step's never-drop-on-
# incomplete-info design). Grepped the whole monorepo first: zero real callers ever passed
# gbif_snapshot_path, same "no external users" bar already used to remove fetch_reference_
# sequences()/expand_consensus_candidates()/read_wildlife_insights_output(). User confirmed
# removal (not just documenting the overlap, not fixing the coalesce gap in place). Removed:
# gbif_snapshot_path param + gbif_hashes threaded through .process_one_dataset()/.finalize_entity()/
# .attempt_odm_join() (5 internal call sites) + .load_gbif_hashes()/.deduplicate_against_gbif()
# themselves; roxygen @details/@examples updated to point at stack_occurrences()'s
# collapse_duplicate_occasions instead; unused dplyr::coalesce/readr::read_tsv @importFrom entries
# dropped from this file now that nothing in it calls them. devtools::test() 0 failures (553, up
# from 549 -- net +4 after removing the params from 11 existing test call sites, no dedicated
# tests existed for the two deleted internal helpers themselves), devtools::check() 0 errors/0
# warnings/1 note (same pre-existing clock-check NOTE).
# Previous update, 2026-07-23 (Sonnet 5 -- new fetch_inat_occurrences(), implementing
# ecosystem_docs/REENTRY_PROMPT_domestic_food_species_priors.md's non-GBIF occurrence source.
# Unlike check_inat_range() (point-in-polygon against a thresholded range geomodel),
# this counts real individual iNaturalist observation records near a point via the
# /v1/observations search endpoint, with explicit captive ("any"/"true"/"false") and
# quality_grade ("any"/"casual"/"needs_id"/"research") filters -- quality_grade = "casual"
# (or captive = "true") is where standard GBIF-style occurrence indexing structurally
# excludes/under-indexes captive pets/livestock and cultivated/ornamental plants, exactly
# the gap this function exists to surface. Reuses .inat_taxon_id() (check_inat_range.R,
# same package) for name resolution rather than reimplementing it; a single per_page=1
# request per taxon reads iNaturalist's own total_results field, so no per-record download
# is needed. Consumed by TaxaExpect::generate_domestic_food_priors() -- see that package's
# CLAUDE.md for the full three-vector design this implements. devtools::test() 0 failures
# (539, up from 506), devtools::check() 0/0/0. Reinstalled to ~/Library/R/4.0/library.
# Previous update, 2026-07-23, continued yet further (Sonnet 5 -- filter_gbif_quality()'s
# institution check split out from the other five CoordinateCleaner removal checks: it now
# FLAGS, never removes. Prompted directly by the user reviewing the real 29 Mugu institution
# matches and recognizing a structural problem cc_inst() can't resolve on its own -- field
# stations/marine labs are often sited exactly where good habitat is (the live-fish-near-a-
# university-botanical-garden-pond case), so proximity alone can't be auto-removed the way an
# equal-coordinate or near-GBIF-HQ match can. `exclude_institution` renamed `flag_institution`
# (default TRUE still, but now means "flag" not "remove" -- no existing caller was passing it
# explicitly, so no real fallout). Institution-flagged rows are RETAINED with four new columns
# (institution_flag/name/type/dist_m) rather than moving to removed_records; step 9 (the other
# five checks) now runs first, so a record failing BOTH a removal check and the institution
# check is removed, never reaching the flagging step at all. New .nearest_institution() internal
# helper (haversine against CoordinateCleaner::institutions, only for already-flagged rows) 
# recovers which specific institution matched, since cc_inst(value="flagged") only returns a
# boolean. New TaxaHabitat::flag_institution_candidates() (classify stage, mirrors
# flag_habitat_inconsistencies()'s role) tiers flagged rows "high"/"low"/"ambiguous" by
# crossing the matched institution's real type (Herbarium/Botanic_garden/Zoo/Museum/University/
# Research_centre -- verified via source, not guessed) against the record's kingdom; a real bug
# (all-NA logical-index subsetting, not the count in the summary message alone) was found and
# fixed for records whose matched institution has no recorded type. The interactive map review
# gadget (mirroring review_spatial_flags(), ~950 lines) is intentionally NOT built yet -- scoped
# but deferred given real time constraints flagged mid-session; see TaxaHabitat/CLAUDE.md and
# [[project_geographic_outlier_check]] for the resume point. devtools::test() 0 failures (515,
# up from 506), devtools::check() 0/0/0. Reinstalled to ~/Library/R/4.0/library.
# Previous update, 2026-07-23, continued (Sonnet 5 -- filter_gbif_quality() redesigned around a
# full removal audit trail, prompted by the user asking why the new cc_cen/cc_cap/cc_inst
# checks (below) produced no visible output columns, then explicitly wanting to see what got
# removed and why -- both to catch/repair mistakenly-excluded records and as raw material for
# reporting real GBIF data-quality problems (bad georeferencing, institution/centroid-snapped
# coordinates) back to GBIF, plus as transparency when two users' filter arguments diverge.
# Scope grew from "just the CoordinateCleaner step" to all nine filter steps at the user's own
# request. New: attr(result, "removed_records") is ALWAYS present (a data frame, possibly zero
# rows, never NULL) with every original column plus filter_reason -- "missing_coordinates",
# "absent_occurrence", "basis_of_record", "flagged_issue_code:<code>" (which bad_issues code
# specifically matched, not just that one did), "coordinate_uncertainty",
# "coordinate_decimal_precision", "edna_keyword", "no_species_id", or one-or-more of
# "equal_coordinates"/"near_zero"/"near_gbif_hq"/"country_centroid"/"capital"/"institution"
# joined with ";" when a record fails more than one CoordinateCleaner check at once (real,
# tested case: (0.01, 0.01) is simultaneously equal-coordinate AND near-zero). Internals fully
# rewritten (each step now computes an explicit keep mask instead of piping through
# dplyr::filter()) -- this let me fix, for free, a real pre-existing bug flagged but left alone
# on 2026-07-20: steps 7/8 never reassigned the stale n_current tracking variable, so their
# printed "Removed N records" message could overcount when both steps removed rows in the same
# call; the new mask-based counting has no equivalent staleness to have. Return contract is
# still just the cleaned data frame (fully backward compatible) -- removed_records is purely
# additive via attr(). 5 new tests, including a real double-simultaneous-CC-reason case. A real
# bug caught in my own first draft before shipping: the exact "split-string sprintf" footgun
# already documented in this file's own Known Footguns section (multiple string args passed to
# sprintf() alongside the real one, silently not concatenated) -- caught by re-reading my own
# diff rather than trusting it, fixed with paste0() before sprintf(), matching every other
# multi-line message already in this function. Benchmarked at real Mugu scale (132k rows) under
# an artificial ~80%-removal stress test (far harsher than real GBIF data, which removed ~7.5%
# on the actual Mugu run): 11.7s, up from 1.37s on the earlier zero-removal benchmark -- a real,
# expected cost (each step now subsets both kept and removed rows, not just kept), not a
# concern for a function that isn't called in a tight loop. devtools::test() 0 failures (506,
# up from 494), devtools::check() 0/0/0. Reinstalled to ~/Library/R/4.0/library.
# Previous update, 2026-07-23 (Sonnet 5 -- filter_gbif_quality() gains the three CoordinateCleaner
# checks deferred from the original design conversation: cc_cen()/cc_cap()/cc_inst() (near a
# country/province centroid, near a national capital, near a biodiversity institution), all
# three called with only lon/lat/value supplied so their ref = NULL default resolves to that
# package's own bundled countryref/institutions data automatically -- confirmed via direct
# source inspection, no network call, no hand-copied buffer/reference constants (same principle
# already applied to cc_equ/cc_zero/cc_gbif). Confirmed these three don't share cc_outl()'s
# record-count-triggered raster-approximation risk -- they're plain per-row point-in-buffer
# tests against a fixed external reference set, no species-conditional branching at all.
# Benchmarked at Mugu's real ~122k-row scale: 1.37s, no performance concern (the reference data
# is cropped to the query's own bounding box before the buffer test, so cost doesn't scale with
# row count). New tests use REAL coordinates pulled live from CoordinateCleaner's own bundled
# countryref/institutions data rather than guessed values, so correctness holds regardless of
# the package's exact buffer defaults. check_geographic_outliers() also wired into all three
# real PtConception workflow scripts (PtConceptionWorkflow_12S_single_site.R, _18S_2_single_
# site.R, _12S_multi_site.R -- outside this monorepo, not under git) using the identical pattern
# already validated on both real Mugu workflows, not yet run live against real PtConception
# data. devtools::test() 0 failures (494, up from 487), devtools::check() 0/0/0. Reinstalled to
# ~/Library/R/4.0/library. See this file's Session Notes for the full record.
# Previous update, 2026-07-20, continued yet further (Sonnet 5 -- a real GBIF API timeout during
# the user's own re-verification of the cc_outl() fix (below) surfaced a second, independent
# real bug in fetch_gbif_occurrences()'s checkpoint logic, pre-existing, unrelated to today's
# other changes. With keys split into chunks, global_pos was advanced by the FULL chunk size
# even when a chunk aborted partway through -- so the checkpoint's remaining_keys was computed
# from a position AFTER the whole aborted chunk, silently excluding the very key that failed
# (and any others queued after it in that same chunk) from ever being retried on resume: a
# real violation of this function's own stated "never silently skip a key" design. Also
# produced a misleading "Enable cache_dir for resumable fetches" message on the user's actual
# run even though cache_dir WAS enabled and a real checkpoint HAD been saved after the prior
# chunk -- global_pos coincidentally landed exactly on length(keys), making the (buggy)
# resumability check evaluate false. Fixed: the abort check now runs BEFORE global_pos is
# advanced past the aborting chunk, and the checkpoint's remaining_keys re-includes the WHOLE
# aborting chunk (not just the failed key onward) so a resume cleanly re-fetches it rather than
# risk duplicate rows from any partial success within it. New regression test asserts the
# failed key is present in the saved remaining_keys (it wasn't, under the old logic). No user
# action needed for the checkpoint file from the actual failed run -- resuming with the same
# call still works, since that specific abort happened to land after a real prior-chunk
# checkpoint. devtools::test() 0 failures (487, up from 483), devtools::check() 0/0/0.
# Reinstalled to ~/Library/R/4.0/library. See this file's Session Notes for the full record.
# Previous update, 2026-07-20, continued (Sonnet 5 -- real production bug found and fixed on
# check_geographic_outliers()'s FIRST live run, wired into MuguFishWorkflow.R/
# MuguWilderFishWorkflow.R the same day: CoordinateCleaner::cc_outl()'s "distance" method
# silently switches EVERY species in a single call to a coarser "raster approximation" (its
# own term) whenever ANY ONE species in that call has >=10,000 records -- confirmed directly
# from cc_outl()'s own source (`if (any(record_numbers >= 10000)) warning("Using raster
# approximation.")`, scoped to the whole call, not per species). check_geographic_outliers()
# batches every locally-rare species into one cc_outl() call for efficiency, but a species
# rare in the LOCAL bbox can still be globally common -- one such species in the real
# ~51-species/193,458-record Mugu batch silently degraded every other species' precision,
# clearing a real, obvious ~9,000km outlier (the exact motivating Mugu Pseudotolithus
# epipercus/La Jolla case). Found live with the user: two hypotheses tested and refuted first
# (a gbifID type mismatch between download_gbif_occurrences()'s bit64::integer64 output and
# fetch_gbif_occurrences()'s character output -- ruled out directly, match() handles the
# coercion correctly even unattached; a species-crossing distance bug -- ruled out via a
# synthetic decoy-species reproduction) before the user's own diagnostic re-run surfaced the
# literal "Using raster approximation" warning, which traced directly to cc_outl()'s source.
# Fixed: cc_outl() now called once PER SPECIES instead of once for the whole batch, so the
# raster-mode decision is scoped to each species' own record count. New regression test
# (mocks CoordinateCleaner::cc_outl() directly, asserts one call per species) added rather
# than trying to synthesize a 10,000+ row fixture to reproduce the raster branch itself --
# the original unit tests (max ~17 rows) never exercised this path at all, the same "check
# dataset scale before trusting synthetic tests generalize" lesson this ecosystem has hit
# before (see TaxaLikely's restore_suppressed_candidates() history). devtools::test() 0
# failures (483, up from 481), devtools::check() 0/0/0. Reinstalled to
# ~/Library/R/4.0/library. See this file's Session Notes for the full record.
# Previous update, 2026-07-20 (Sonnet 5 -- new check_geographic_outliers(): for GBIF species
# with few records inside a bbox-scoped local search (default threshold n<5), fetches that
# species' unrestricted global GBIF distribution (fetch_gbif_occurrences(geometry = NULL),
# newly supported -- geometry was previously a required WKT string; a real nchar(NULL)
# checkpoint-signature bug was fixed alongside it) and runs CoordinateCleaner::cc_outl()
# against it, flagging a local record that's a geographic outlier relative to the species'
# real range (the general version of Mugu's real Pseudotolithus epipercus/La Jolla case --
# see [[project_edge_case_error_taxa_design]]). filter_gbif_quality() also gains three new
# CoordinateCleaner-backed checks (cc_equ/cc_zero/cc_gbif), default TRUE -- a real behavioral
# default change for every existing caller, not just an addition (see that function's
# Function Inventory entry below for the affected real call sites). CoordinateCleaner added
# to Suggests only, deliberately -- its cc_sea()/cc_coun()/cc_urb() functions need terra/
# rnaturalearth, but those three don't fit this ecosystem (marine-eDNA-hostile or already
# redundant with GBIF's own issue-code filtering) and aren't used; the functions actually
# called here don't need those dependencies. check_inat_range() (Session 118) found MISSING
# from this file's own Function Inventory table and Next Steps TODO list while working
# nearby -- real doc drift, corrected same session, not implemented new. devtools::test()
# 0 failures (481, up from 459), devtools::check() 0 errors/0 warnings/0 notes. Reinstalled
# to ~/Library/R/4.0/library.
# Previous update, 2026-07-09 (Session 148 -- full code + domain review against
# inst/Code and Domain Review 2.Rmd, findings and fixes in taxafetch_review.Rmd at the
# TaxaID root. Two real, fixed issues: an SSRF gap in the DataONE pipeline (data_url read
# verbatim from third-party EML metadata with no host restriction -- fixed via a
# pasta.lternet.edu/pasta.edirepository.org allowlist) and a homonym-misresolution gap in
# get_keys_from_context()'s HIGHERRANK recovery path (name_lookup() fallback dropped all
# kingdom context -- fixed by narrowing lookup hits to the row's own kingdom before voting).
# Also fixed: biotime_fetch.R conflating unparseable ABUNDANCE/BIOMAS with confirmed
# occurrenceStatus = "absent" (now NA); filter_gbif_quality()'s eDNA-exclusion pattern was
# overly broad ("bulk sample"/"water sample" alone, narrowed to the three eDNA-specific
# terms); doc-only clarifications for make_bbox_wkt()'s latitude-dependent km caveat and
# get_gbif_occurrences()'s rank_filter subspecies-exclusion behavior; a zip-slip defense-in-
# depth check added to download_gbif_occurrences(). Corrects Session 131's Pass 7a note
# ("no high-confidence vulnerabilities found") -- that pass did not live-test DataONE's EML
# handling against real PASTA data, which is what surfaced the SSRF gap this session.
# devtools::test(): 459 expectations (up from 434), 0 failures. devtools::check(): 0 errors,
# 0 warnings, 0 notes. See Session 148 note below for the full record. Session 140 --
# fetch_occurrences_by_taxon() added: taxon-centric
# batched GBIF fetch, implementing the general-fix design from
# ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md. stack_occurrences() also
# gained a gbifID dedup step. See Session 140 note below for the full record. Session 134b --
# define_search_polygon() and group_observations_by_bbox() moved OUT of this package:
# define_search_polygon() -> TaxaTools (shared gadget, now also used for TaxaMatch's spatial
# grouping), group_observations_by_bbox() -> TaxaMatch (it operates on
# TaxaMatch::build_site_table()'s output; a spatial-grouping concern, not a fetch concern).
# shiny/miniUI/leaflet dropped from this package's Suggests accordingly. See TaxaTools/CLAUDE.md
# and TaxaMatch/CLAUDE.md Session 134b notes for the new homes.)

---

## Package Purpose
Occurrence data acquisition (GBIF, DataONE, PDF, literature search) and source combination.
Habitat assignment and spatial QAQC are now in **TaxaHabitat**. LLM provider functions are
now in **TaxaTools**. Split from TaxaExpect in Session 19; further split in Session 28.

**Why GBIF is the primary occurrence source (not a per-platform fetcher per source):**
GBIF is an *aggregator* -- it already ingests and republishes records from eBird,
iNaturalist, Observation.org, OBIS, and most natural history museum/herbarium
collections, each as its own registered dataset/publisher, alongside GBIF's own directly
mobilized data. A record originating on any of those platforms that has been published to
GBIF already flows into TaxaFetch through the existing `get_gbif_occurrences()` pipeline
with no extra code. Building a separate per-platform fetcher (an Observation.org-specific
function, an eBird-specific function, etc.) would be redundant for any data those
platforms already publish to GBIF -- the one GBIF-facing function is deliberately meant to
cover many public data sources at once. A dedicated non-GBIF fetcher is only justified for
a source with data GBIF genuinely lacks (not yet aggregated, embargoed, or offering richer
fields than its GBIF-published subset) -- iNaturalist's `check_inat_range()` is exactly
this kind of case: it hits iNaturalist's own geomodel API for range polygons, which GBIF's
occurrence records do not carry at all, rather than duplicating iNaturalist's occurrence
data (already available via GBIF).

**Dependency chain:** TaxaTools → TaxaFetch → TaxaHabitat → TaxaExpect → TaxaAssign/TaxaMatch

---

## Function Inventory

**Note (Session 134b):** the interactive polygon gadget formerly documented here,
`define_search_polygon()`, is now `TaxaTools::define_search_polygon()` -- moved so
TaxaMatch's `group_observations_by_bbox()` (spatial grouping) can share it with this
package's search-area use. `make_bbox_wkt()` below still links to it for the
non-interactive-vs-interactive comparison.

### DataONE / GBIF pipeline

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `stack_occurrences()` | Row-bind occurrence data frames; accepts list OR `...`; drops NULL; adds `point_id`; single-frame OK. **Never removes any rows** -- deduplication is `dedupe_occurrences()`'s job (see below), a deliberate split (2026-07-23) from this function's original combined design. Row count is always exactly the sum of the input frames' row counts. | Complete | R/stack_occurrences.R |
| `dedupe_occurrences()` | **2026-07-23, new -- split out of `stack_occurrences()`.** Takes a single data frame (stacked or not) and removes duplicates via two independent mechanisms: (1) exact-`gbifID` match (moved from `stack_occurrences()`, Session 140 origin) -- defense-in-depth against the same GBIF record being counted twice (overlapping search geometry, coincidental multi-taxon overlap); (2) `collapse_duplicate_occasions` (default `TRUE`, moved from `stack_occurrences()`, 2026-07-23 origin) -- content-based match on `taxon_col` (default `scientificName`, case-insensitive) x `date_col` (default `eventDate`, falls back to `year`/`month`/`day`) x `lat_col`/`lon_col` rounded to `coord_precision` (default 3 d.p.), catching repeat reports of one detection occasion across DIFFERENT records/platforms/observers (e.g. several eBird checklists for one rare-bird-alert individual, several iNaturalist uploads from one bioblitz) that the `gbifID` check can't touch since each is a genuinely distinct record. **Why a separate function, not a `stack_occurrences()` param:** both mechanisms can fire within a SINGLE, un-stacked source (one `get_gbif_occurrences()` call can already contain overlapping-key `gbifID` duplicates or multi-platform occasion duplicates, since GBIF itself aggregates eBird/iNaturalist/Observation.org/etc.) -- bundling dedup inside a function literally named "stack" invited a real risk that a single-source caller would read the name, conclude stacking didn't apply to them, and skip deduplication entirely (raised by the user directly). Motivated by `TaxaExpect::prepare_model_dataframe()` counting raw records as both the binomial numerator (`n_species`) and shared effort denominator (`n_total_at_site`) -- uncollapsed repeat reports inflate a species' modeled relative detection frequency directly. Content-based match, so a row missing any key component is always kept; silent no-op when a check's key columns aren't present at all. Refreshes a `report_params` attribute's `n_records` (and adds `n_duplicates_removed`) if present. | Complete | R/dedupe_occurrences.R |
| `make_bbox_wkt()` | Build WKT POLYGON bounding box (scripted, non-interactive) | Complete | R/make_bbox_wkt.R |
| `get_keys_from_context()` | Resolve hierarchy dataframe to GBIF usage keys. **Session 148:** its `HIGHERRANK`-recovery path (`.recover_higherrank()`) now narrows `rgbif::name_lookup()` hits to the row's own kingdom (when available) before majority-voting a `nubKey`, closing a homonym-misresolution gap; the resulting `matchType = "LOOKUP_RECOVERED"` is now documented and included in the "review these rows" advice. | Complete | R/get_keys_from_context.R |
| `fetch_gbif_occurrences()` | Download occurrence records for GBIF taxon keys via GBIF occurrence API. `max_retries` (default 4) applies exponential backoff on HTTP 429 (30/60/120/240s) and HTTP 503 (5/10/20/40s). Any exhausted retry aborts immediately (no silent skipping). `cache_dir` (default: user cache dir) saves per-chunk checkpoints; re-running with same args resumes automatically. **Use for ≤~50 keys; no GBIF account required.** See `download_gbif_occurrences()` for large key sets. **2026-07-20:** `geometry` now accepts `NULL` for an unrestricted global search (previously required a WKT string); the checkpoint-signature helper's `nchar(NULL)` bug (returned `integer(0)`, would have broken `sprintf`) fixed alongside it. Added for `check_geographic_outliers()`, below. **2026-07-20, continued:** real, pre-existing checkpoint bug fixed, found via a real GBIF timeout mid-run -- `global_pos` was previously advanced by a chunk's FULL size even when that chunk aborted partway through, so the saved checkpoint's `remaining_keys` silently excluded the key that actually failed (and any others queued after it in the same chunk), meaning it would never be retried on resume. Also caused a misleading "Enable cache_dir for resumable fetches" message on a real run where `cache_dir` genuinely was enabled and a checkpoint genuinely had been saved. Fixed: abort check now runs before `global_pos` advances past the aborting chunk; the checkpoint re-includes the WHOLE aborting chunk (not just the failed key onward) so resume can't produce duplicate rows from a partial in-chunk success. | Complete | R/fetch_gbif_occurrences.R |
| `download_gbif_occurrences()` | Async bulk download via GBIF download API — use for large key sets (100s–1000s) to avoid HTTP 429 rate limits. Submits `occ_download()` job; polls until complete; downloads zip to `cache_dir`. **Requires GBIF account** (`GBIF_USER`/`GBIF_PWD`/`GBIF_EMAIL` in `~/.Renviron`). Key design notes: (1) uses rank-specific OR predicate (`familyKey`/`genusKey`/`speciesKey`/`taxonKey`) because download API `taxonKey` is exact-match only, not hierarchical; (2) `limit` is per-key (group_by taxonKey + slice_head); (3) signature-based cache — re-runs with same params skip GBIF wait and load from cached zip; (4) `select_cols` trims SIMPLE_CSV to needed columns at fread time (~10× size reduction); (5) SIMPLE_CSV `issue` column renamed to `issues` for `filter_gbif_quality()` compatibility — implemented and verified working (Session 131; a Session 129 note here previously claimed otherwise, incorrectly); (6) `basis_keep` applied server-side. `bibliographicCitation` = GBIF download portal URL (avoids `occ_download_meta()` hang). Called directly, `select_cols` should reference SIMPLE_CSV's native `issue` (singular) name if customized — the function renames the output column to `issues` regardless. **2026-09-04:** `overwrite = TRUE` no longer orphans the superseded zip -- in an interactive session it shows the cached zip's date/size and asks whether to overwrite or keep it (`utils::menu()`); a non-interactive session proceeds straight to a fresh download as before, but either way the stale zip is deleted once the new one lands. Also now prints a cache-size summary after every run and offers `taxafetch_clear_cache()` once the cache passes 1GB. | Complete | R/download_gbif_occurrences.R |
| `taxafetch_clear_cache()` | **2026-09-04, new.** Reports/clears TaxaFetch's on-disk cache (GBIF zips + metadata, GBIF checkpoints, iNat range GeoJSON, and -- if ever enabled -- `search_literature()`'s OpenAlex cache). `cache_dir`/`older_than_days`/`dry_run` -- same interface as `TaxaLikely::taxalikely_clear_cache()`. `orphans_only = TRUE` targets only zips no longer referenced by any current `download_gbif_occurrences()` metadata file (i.e. leftovers from a pre-fix `overwrite = TRUE` run) -- the "keep the most recent cache per query, remove only stale leftovers" mode; every current zip, every metadata file, every checkpoint, and every iNat range file are left untouched. Built on `TaxaTools::list_cache_files()`/`report_and_clear_cache()` (shared engine, also used by `taxalikely_clear_cache()`) -- orphan detection is the only genuinely TaxaFetch-specific piece, layered in front as a pre-filter. | Complete | R/taxafetch_clear_cache.R |
| `get_gbif_occurrences()` | **Session 129 — recommended entry point**, not a replacement for the two functions above (neither is modified). Picks `fetch_gbif_occurrences()` vs `download_gbif_occurrences()` by `key_threshold` (default 50, matching both functions' own documented guidance and the manual dispatch pattern the Layer-1 tutorial already used) and standardizes both paths to one column contract. `rank_filter = "species"` (default) is a post-fetch filter only — neither GBIF API exposes a taxonomic-rank predicate to filter server-side. `columns = "standard"` (default) / `"all"` / custom vector. `familyKey`/`genusKey` are `NA` on the download path — SIMPLE_CSV doesn't carry them at all, not fixable by this wrapper. Translates the wrapper's canonical `issues` column name back to SIMPLE_CSV's native `issue` when building `select_cols` for the download path (needed because `select_cols` matches at import time, before `download_gbif_occurrences()`'s own rename runs) — this is the only issue/issues handling the wrapper does; see `download_gbif_occurrences()`'s entry above for the Session 131 correction to a false "cross-path bug" claimed here previously. | Complete | R/get_gbif_occurrences.R |
| `fetch_occurrences_by_taxon()` | **Session 140 — taxon-centric batched fetch.** Groups a fetch scope (one row per (site, candidate taxon) pair: `taxon_key` + `geometry` WKT) by taxon key instead of by observation/site: unions each taxon key's own geometry via `sf::st_union()` (dissolving the duplicate-record risk when two site boxes for the same taxon overlap), then combines different taxon keys that end up with an identical unioned geometry into one multi-key `get_gbif_occurrences()` call (`combine_shared_geometry = TRUE`, default). Neither `get_gbif_occurrences()` nor its own backends are modified — this is a pure call-grouping layer above it. Does not expose `rgbif`'s `geom_big`/`geom_size`/`geom_n` WKT-complexity escape valve and does not characterize GBIF's real WKT-size ceiling (documented as a known limitation, not silently masked). See `ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md` for the full design discussion this implements. | Complete | R/fetch_occurrences_by_taxon.R |
| `filter_gbif_quality()` | Filter GBIF records by quality criteria; default `max_coord_uncertainty = 500` m; NA retained. `exclude_absent = TRUE` removes records where `occurrenceStatus = "ABSENT"` (explicit non-detections from systematic surveys — must not be used as presence data). `require_species = FALSE` (set TRUE when querying by family/genus key — GBIF returns all ranks within the taxon including genus-only records that lack a species value). Filter order: coordinates → absent occurrences → basis of record → issue codes → coordinate uncertainty → decimal-place precision → eDNA → species-level requirement → CoordinateCleaner checks. **Session 148:** the eDNA-exclusion pattern narrowed to `edna`/`environmental dna`/`metabarcod` -- dropped the generic `bulk sample`/`water sample` phrases, which risked over-excluding legitimate non-eDNA presence data. **2026-07-20 (behavioral default change):** new filter step 9 calls `CoordinateCleaner::cc_equ()`/`cc_zero()`/`cc_gbif()` (identical lat/lon, near-(0,0), near GBIF's Copenhagen HQ) via new `exclude_equal_coords`/`exclude_near_zero`/`exclude_near_gbif_hq` params, each default `TRUE`. Uses that package's own internal buffer defaults rather than hand-copied constants -- see the function's own roxygen `@details` for why. Skips with a message (not an error) if `CoordinateCleaner` is not installed, matching every other optional-column/optional-package filter in this function. Every real in-repo caller (`TaxaExpect::build_priors()`, `TaxaExpect/inst/workflows/generate_priors_workflow.R`, `TaxaAssign/inst/workflows/camera_trap_posterior_workflow.R`, `TaxaWizard/inst/graph/snippets/taxa_to_occ.R`) calls with no override, so all now pick up the new checks automatically wherever `CoordinateCleaner` happens to be installed. **2026-07-23:** the three checks originally deferred (Tier 2, needing bundled reference data rather than being fully self-contained) are now also in: `exclude_country_centroid`/`exclude_capital`/`exclude_institution` call `CoordinateCleaner::cc_cen()`/`cc_cap()`/`cc_inst()`, each default `TRUE`, same skip-with-message-if-absent convention, same "use the package's own defaults, don't hand-copy them" principle. All three resolve their `ref = NULL` default to bundled `countryref`/`institutions` data automatically (confirmed via source inspection -- no network call). Unlike `cc_outl()` (used by `check_geographic_outliers()`), none of these three branch on record count or species, so they don't share that function's batching risk; benchmarked at 1.37s for 122k rows (Mugu's real scale) -- cost doesn't grow with row count since the reference data is cropped to the query's own bbox first. Filter order is now nine steps deep: filter step 9 covers all six `CoordinateCleaner` checks together. Every real in-repo caller above picks these three up automatically too, same as the first three. **2026-07-23, continued:** every removed row across all nine filter steps is now preserved, not just counted -- `attr(result, "removed_records")` is always present (never `NULL`, possibly zero rows), one row per removed record with every original column plus `filter_reason` (per-filter tag; GBIF issue-code and CoordinateCleaner removals get the SPECIFIC matched code/check(s), e.g. `"flagged_issue_code:COORDINATE_OUT_OF_RANGE"` or `"equal_coordinates;near_zero"` for a double-hit). Return value itself is unchanged (still just the cleaned data frame) -- fully backward compatible, purely additive via `attr()`. Prompted by the user wanting to (a) audit/repair mistakenly-excluded records, (b) surface real GBIF data-quality problems worth reporting back to GBIF (every removed row keeps `gbifID`/`datasetKey` for exactly that), (c) make two users' differing filter arguments produce comparable, inspectable results rather than silently different ones. Internals fully rewritten to explicit keep-masks (no more `dplyr::filter()`), which incidentally fixed a real pre-existing message-accuracy bug (steps 7/8 never refreshed a stale count variable). **2026-07-23, continued yet further (behavioral default change, signature change):** `exclude_institution` renamed `flag_institution` (default `TRUE` unchanged) and split out of the other five `CoordinateCleaner` checks -- it now **flags, never removes**. Retained rows near a biodiversity institution get four new columns (`institution_flag`, `institution_name`, `institution_type`, `institution_dist_m`, via new internal `.nearest_institution()`) instead of moving to `removed_records`; `"institution"` can no longer appear as a `filter_reason` value. The other five checks (now their own step 9, run before institution flagging as step 10) are unaffected -- a record failing both a removal check and the institution check is removed and never reaches the flagging step. Consumed by `TaxaHabitat::flag_institution_candidates()`. **2026-07-23, continued yet further:** `.nearest_institution()` gained two more columns, `institution_lon`/`institution_lat` -- the matched institution's OWN coordinates (distinct from the record's own), needed so `TaxaHabitat::review_institution_flags()` can plot the flagged record and its matched institution together on one map without re-querying `CoordinateCleaner::institutions` itself. Six institution columns total now. | Complete | R/filter_gbif_quality.R |
| `check_geographic_outliers()` | **2026-07-20, new.** Flags bbox-scoped occurrence records that are geographic outliers against a species' own global GBIF distribution -- the generic version of "single citizen-science record from the wrong continent slips into a local species list" (motivating real case: Mugu's *Pseudotolithus epipercus*, an African species with one errant La Jolla observation, see `[[project_edge_case_error_taxa_design]]` in the memory system). For species with fewer than `min_local_n` (default 5) local records, fetches that species' unrestricted global occurrences via `fetch_gbif_occurrences(geometry = NULL)` and runs `CoordinateCleaner::cc_outl()` (`method = "distance"`, `tdi = 1000` km default) **once per species** against its own global cloud. Well-supported local species are never checked -- the global fetch is the expensive step. **2026-07-20, same-day fix (real production bug, first live run):** originally called `cc_outl()` once across the WHOLE batch of rare species combined -- that function's `"distance"` method silently switches every species in a single call to a coarser raster approximation whenever any ONE species in that call has >=10,000 records, and a locally-rare species can still be globally common. This let one common species in a real ~51-species Mugu batch silently degrade every other species' precision, clearing a real, obvious ~9,000km outlier (the exact motivating *Pseudotolithus epipercus* case). Fixed by scoping each `cc_outl()` call to one species at a time. Adds `local_n`/`global_n_unique`/`outlier_status` columns; `outlier_status` is always one of `"not_tested_sufficient_local_data"` / `"insufficient_global_data"` / `"outlier"` / `"consistent"` -- never a bare logical, so "not tested" and "tested and passed" stay distinct (mirrors `check_inat_range()`'s `range_status` convention, immediately below). `min_occs` (default 7, matching `cc_outl()`'s own default) is enforced explicitly rather than trusted to `cc_outl()`'s own silent-pass-below-threshold behavior, since that function's own warning about it is suppressed here (redundant with the structured status column). Requires `CoordinateCleaner` (`Suggests`, hard error if missing -- no sensible fallback exists, unlike `filter_gbif_quality()`'s graceful per-check skip). | Complete | R/check_geographic_outliers.R |
| `check_inat_range()` | Point-in-polygon range check against iNaturalist geomodel range polygons, for the dark-diversity use case (eDNA detections absent from the occurrence database, checked for range plausibility as a prior-boost signal). Implemented Session 118 -- **missing from this table until 2026-07-20**, a real doc-drift gap; see the corrected Next Steps entry below. Returns `in_range`, `range_status` (`"in_range"`/`"out_of_range"`/`"taxon_not_found"`/`"no_polygon"`), `n_observations`, `iconic_taxon_name`, `inat_kingdom`. Evidence is asymmetric by design: `in_range = FALSE` must not suppress a prior (false negatives are common for aquatic/marine taxa given low iNaturalist observer effort there) -- worth remembering before using this as a fallback alongside `check_geographic_outliers()`, whose primary use case (12S/18S fish eDNA) is exactly the domain this function is weakest in. Downstream: `TaxaAssign::adjust_inat_range_priors()`. | Complete | R/check_inat_range.R |
| `fetch_inat_occurrences()` | **2026-07-23, new.** Counts real local iNaturalist observation records (not a range-polygon test) via `/v1/observations`, with explicit `captive` (`"any"`/`"true"`/`"false"`) and `quality_grade` (`"any"`/`"casual"`/`"needs_id"`/`"research"`) filters -- `quality_grade = "casual"` or `captive = "true"` surfaces exactly the captive/cultivated organisms standard GBIF-style indexing excludes. Reuses `.inat_taxon_id()` (this file) for name resolution; a single `per_page = 1` request per taxon reads `total_results` directly, no per-record download needed. **2026-07-24:** gains `inat_kingdom` (via `.iconic_to_kingdom()`, same lookup `check_inat_range()` uses) so a caller can detect a possible cross-kingdom homonym mismatch -- iNaturalist resolves names against its own curated taxonomy, not NCBI's or GBIF's. Non-GBIF occurrence source for `TaxaExpect::generate_domestic_food_priors()` -- see that package's CLAUDE.md for the full design, including how it consumes `inat_kingdom`. | Complete | R/fetch_inat_occurrences.R |
| `report_fetch()` | Generate `report_section` summarizing occurrence fetch results for `assemble_report()` | Complete | R/report_fetch.R |
| `read_biotime_study()` | Read a BioTime study CSV into a standardized occurrence tibble. **Session 148:** `occurrenceStatus` is now `NA` (not `"absent"`) when neither `ABUNDANCE` nor `BIOMAS` parses to a number, since an unparseable/missing value is not a confirmed non-detection. | Complete | R/biotime_fetch.R |
| `screen_eml_columns()` | Fetch EML; check bbox overlap; detect lat/lon columns | Complete | R/dataone_eml_screen.R |
| `preview_dataone_occurrences()` | Pre-download scout; `dataone_preview` S3 class | Complete | R/dataone_preview.R |
| `print.dataone_preview()` | S3 print method | Complete | R/dataone_preview.R |
| `search_dataone()` | Legacy convenience search | Complete | R/dataone_occurrence_search.R |
| `fetch_dataone_eml()` | Fetch and parse EML XML for one PASTA dataset ID | Complete | R/dataone_occurrence_search.R |
| `fetch_dataone_occurrences()` | Download occurrence records; six-pass architecture. **2026-07-23:** `gbif_snapshot_path` (its own GBIF-vs-DataONE content-based dedup) removed -- zero real callers, superseded by `stack_occurrences(collapse_duplicate_occasions=)`, which does the same key-formula check more safely (never matches on incomplete data) on the in-memory combined output. | Complete | R/dataone_standardize.R |
| `harvest_dataone_catalog()` | Paginated full PASTA Solr harvest; disk-cached | Complete | R/dataone_catalog.R |
| `build_geo_prompt()` | Build `geo_prompt` S3 for LLM geographic screening — DataONE path only | Complete | R/dataone_geo_screening.R |
| `parse_geo_screening_response()` | Parse YES/NO LLM response → filtered candidate tibble | Complete | R/dataone_geo_screening.R |
| `build_taxon_screen_prompt()` | Build `taxon_prompt` S3; `geo_scope` param enables combined taxon+geo screening | Complete | R/dataone_taxon_screening.R |
| `print.taxon_prompt()` | S3 print method; shows `geo_scope` when present | Complete | R/dataone_taxon_screening.R |
| `parse_taxon_screening_response()` | Parse LLM response → `taxon_match` + optional `geo_match`; auto-drops stale columns | Complete | R/dataone_taxon_screening.R |

### Literature search pipeline (Session 25)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `search_literature()` | Query OpenAlex API; reverse-geocode bbox via Nominatim; return catalog tibble | Complete | R/literature_search.R |
| `download_literature_pdfs()` | Download PDFs; adds `local_pdf_path`; validates PDF magic bytes; `overwrite` param | Complete | R/literature_search.R |

### PDF pipeline (Sessions 23–25)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `extract_pdf_text()` | Extract text by section; returns `$sections`, `$page_map`, `$has_headers`, `$n_pages`, `$pdf_path` | Complete | R/pdf_text.R |
| `call_api_pdf()` | Send selected PDF pages as images to a vision-capable LLM via `TaxaTools::call_api()` -- any registered provider (Anthropic, Gemini, OpenAI, Ollama), not Anthropic-only. **2026-08:** this table row and the file's own header comment previously claimed "Anthropic-only" -- stale, predating Session 87's provider-generalization; the function body itself already dispatched through `call_api()` before this session, only the docs were wrong. | Complete | R/pdf_api.R |
| `screen_pdf_structure()` | Five-axis characterisation; `llm_fn` param | Complete | R/pdf_characterize.R |
| `print.pdf_structure()` | S3 print method | Complete | R/pdf_characterize.R |
| `build_pdf_extract_prompt()` | Configure extraction prompt; `dpi` param (default 150L); `chunk_pages` param | Complete | R/pdf_extract.R |
| `print.pdf_extract_prompt()` | S3 print method | Complete | R/pdf_extract.R |
| `parse_pdf_extract_response()` | CSV → DwC tibble; strips subspecies; expands abbreviations | Complete | R/pdf_extract.R |
| `build_pdf_screen_prompt()` | Stage 1 abstract screener | Planned | R/pdf_screen.R |
| `parse_pdf_screen_response()` | Parse Stage 1 screening response | Planned | R/pdf_screen.R |

### Functions moved in Session 28 (now in other packages)

| Function | Now in | File |
|---|---|---|
| `call_anthropic_api()` | TaxaTools | R/llm_api_utils.R |
| `call_gemini_api()` | TaxaTools | R/llm_api_utils.R |
| `call_openai_api()` | TaxaTools | R/llm_api_utils.R |
| `call_ollama_api()` | TaxaTools | R/llm_api_utils.R |
| `prompt_api()` | TaxaTools | R/llm_api_utils.R |
| `prompt_manual()` | TaxaTools | R/llm_api_utils.R |
| `read_llm_response()` | TaxaTools | R/llm_api_utils.R |
| `parse_hierarchical_habitat_response()` | TaxaHabitat | R/parse_habitat_response.R |
| `build_habitat_prompt()` | TaxaHabitat | R/build_habitat_prompt.R |
| `assign_habitat_biological()` | TaxaHabitat | R/assign_habitat_biological.R |
| `flag_habitat_inconsistencies()` | TaxaHabitat | R/flag_habitat_inconsistencies.R |
| `review_spatial_flags()` | TaxaHabitat | R/review_spatial_flags.R |
| `screen_spatial_formula()` | TaxaHabitat | R/screen_spatial_formula.R |
| (plot helpers) | TaxaHabitat | R/utils_plot.R |

---

## Pipeline Architectures

### DataONE pipeline
```
harvest_dataone_catalog() → build_geo_prompt() → build_taxon_screen_prompt()
  → screen_eml_columns() → preview_dataone_occurrences() → fetch_dataone_occurrences()
  → dedupe_occurrences()
```

### GBIF pipeline
```
make_bbox_wkt()                        [scripted square bbox]
TaxaTools::define_search_polygon()     [interactive polygon gadget — interactive sessions only]
  ↓
get_keys_from_context() → get_gbif_occurrences()           [Session 129: picks the path below by key count]
                            ↳ fetch_gbif_occurrences()      [≤~50 keys, no account]
                            ↳ download_gbif_occurrences()   [100s–1000s keys, account required]
                        → filter_gbif_quality()
                        → dedupe_occurrences()          [2026-07-23 -- call this even with a
                                                          single GBIF source; see its own entry
                                                          below for why]
                        → check_geographic_outliers()   [optional, 2026-07-20 -- species below
                                                          min_local_n only; needs CoordinateCleaner]
```

**Session 140 -- taxon-centric batched fetch (a scope-building layer above `get_gbif_occurrences()`):**
```
build a (taxon_key, geometry) fetch scope, one row per (site, candidate taxon)
  ↓
fetch_occurrences_by_taxon()   [unions each taxon key's own geometry, combines
                                 taxa sharing identical geometry, one call per
                                 group via get_gbif_occurrences()]
  ↓
stack_occurrences()             [row-bind only, Session 140/2026-07-23]
  ↓
dedupe_occurrences()             [gbifID + collapse_duplicate_occasions, 2026-07-23]
```
Use `fetch_occurrences_by_taxon()` instead of calling `get_gbif_occurrences()`
directly whenever the fetch scope spans more than one site/observation and
search areas can overlap or coincide -- see `fetch_occurrences_by_taxon()`'s
own entry above and `inst/TaxaID_Workflow_Template_TEST.R` Section 3 for a
worked example (multi-member cluster + single-observation escalation ladder,
unified into one taxon-key map). `dedupe_occurrences()` is always the last
step regardless -- see its own entry below for why it's separate from
`stack_occurrences()` and needed even for a single source.

### Literature + PDF pipeline
```
search_literature() → build_taxon_screen_prompt(geo_scope=...) [optional]
  → download_literature_pdfs() → extract_pdf_text() → screen_pdf_structure()
  → build_pdf_extract_prompt() → call_api_pdf() → parse_pdf_extract_response()
  → stack_occurrences() → dedupe_occurrences()
```

After TaxaFetch: pass occurrence data to **TaxaHabitat** for habitat assignment.

**Key difference:** `build_geo_prompt()` requires DataONE-specific catalog columns — cannot
be used on OpenAlex output. For the literature path, use `build_taxon_screen_prompt(geo_scope=...)`.

---

## LLM Dispatch Architecture (`llm_fn` pattern)

Provider functions (`call_anthropic_api`, `call_gemini_api`, etc.) live in **TaxaTools**.
Since TaxaFetch imports TaxaTools, they are available directly without `TaxaTools::` prefix.

| Function | Provider | Free? | Key env var |
|---|---|---|---|
| `call_anthropic_api()` | Anthropic | No | `ANTHROPIC_API_KEY` |
| `call_gemini_api()` | Google Gemini | Yes (free tier) | `GEMINI_API_KEY` |
| `call_openai_api()` | OpenAI | No | `OPENAI_API_KEY` |
| `call_ollama_api()` | Ollama (local) | Yes (always) | none |

Non-default model/key via closure:
```r
my_fn <- function(p, ...) TaxaTools::call_gemini_api(p, model = "gemini-2.5-flash")
screen_pdf_structure(pdf_content, llm_fn = my_fn)
```

`call_api_pdf()` is Anthropic-only (vision API); provider-neutral image upload is future work.

---

## Key Notes for Claude

- `search_literature()` output column is `id` (not `catalog_id`) — matches `harvest_dataone_catalog()`
- Always drop stale `geo_match`/`taxon_match` columns before rebuilding screening prompts
- `taxon_match` and `geo_match` from `parse_taxon_screening_response()` are **logical**
- `abstract_chars = 2000L` recommended for literature papers (default 300L is too short)
- HTTP 403 on PDF downloads is a publisher restriction, not a bug
- `OPENALEX_API_KEY` in `~/.Renviron`; free tier is sufficient
- `%||%` is an internal operator defined in `get_keys_from_context.R` and `dataone_standardize.R`
  — do not redefine in other TaxaFetch files
- Habitat assignment is now in **TaxaHabitat** — do not add habitat functions back here

---

## Known Issues

- HTTP 403 on publisher PDF downloads: manual download path in workflow
- Section assignment imperfect for two-column layouts (cosmetic only)
- `build_geo_prompt()` not usable on OpenAlex catalog (DataONE-specific columns)
- `call_api_pdf()` is Anthropic-only; provider-neutral image upload is future work

---

## Next Steps

1. ~~Run `devtools::check()`~~ — verified clean (Session 63)
2. ~~`pdf_screen.R`~~ — resolved: `build_taxon_screen_prompt(geo_scope=...)` already handles literature catalog screening in combined mode (Session 63)
3. ~~`stack_occurrences` tests~~ — already written and passing (22 tests, Session 63)
4. ~~GITA multi-table functions~~ — dropped: `rename_cols()` + `stack_occurrences()` cover the same use case (Session 63)
5. ~~Data source citation capture~~ — implemented (Session 63): `bibliographicCitation` column added to `fetch_gbif_occurrences()`, `standardize_dataone_occurrences()`, `read_biotime_study()`; PDF pipeline already had it via `search_literature()`
6. ~~ReefCheck + Reef Life Survey~~ — resolved (Session 64): both already in GBIF (RLS global reef fish dataset, RCCA rocky reef dataset, Reef Check Taiwan). No separate fetch functions needed.
7. ~~`check_inat_range()`~~ — implemented Session 118 (`R/check_inat_range.R`); this Next Steps entry and the Function Inventory table above both went stale until corrected 2026-07-20 -- see `[[project_inat_image_analyzer]]` in the memory system.
8. **`score_image_inat()`** — implemented Session 119, but lives in **TaxaMatch**, not this package -- see that package's own CLAUDE.md. Not tracked further here.
9. **`check_geographic_outliers()`** — implemented 2026-07-20 (`R/check_geographic_outliers.R`), see the Function Inventory table above.

---

## Test Coverage

| File | Functions covered | Notes |
|---|---|---|
| test-fetch_gbif_occurrences.R | `fetch_gbif_occurrences()`, `.gbif_checkpoint_path()`, `.gbif_default_year_range()` | Mocked rgbif; covers 429 retry/backoff; 2026-07-20 added `geometry = NULL` global-search coverage; 2026-08-08 added `.gbif_checkpoint_path()` NULL-`year_range` crash coverage (real bug found by human review) and `.gbif_default_year_range()`'s call-time current-year computation |
| test-filter_gbif_quality.R | `filter_gbif_quality()` | Fully offline; 2026-07-20 added `cc_equ`/`cc_zero` CoordinateCleaner-check coverage (real package calls, `skip_if_not_installed`); 2026-07-23 added `cc_cen`/`cc_cap`/`cc_inst` coverage using REAL coordinates pulled live from `CoordinateCleaner::countryref`/`institutions` at test time, not guessed/hardcoded -- correctness holds regardless of the package's exact buffer defaults; 2026-07-23 continued: 5 new tests for the `removed_records` attribute (always-present-with-0-rows case, missing-coordinates case, specific-matched-issue-code case, a real double-simultaneous-CC-reason case at (0.01, 0.01), original-column preservation); 2026-07-23 continued yet further: institution tests rewritten for flag-not-remove (asserts row retained + 4 new columns populated, not asserts row removed), a `flag_institution = FALSE` skip test, a removal-check-runs-before-institution-flagging ordering test; 2026-08-08 added `basisOfRecord` case/whitespace-insensitivity coverage (human review) |
| test-check_geographic_outliers.R | `check_geographic_outliers()` | 2026-07-20, **new file**. Mocks `rgbif::occ_data` (same layer as test-fetch_gbif_occurrences.R) so the real `fetch_gbif_occurrences()` and `CoordinateCleaner::cc_outl()` both run underneath -- genuine end-to-end coverage of the outlier/insufficient-data/consistent three-way split, not just the plumbing. Same-day addition: a regression test mocking `CoordinateCleaner::cc_outl()` directly to assert it's called once per species (not once for the whole batch) -- guards the real raster-approximation bug found on first live use; deliberately not a synthetic 10,000+ row fixture, which would be slow and still wouldn't exercise the actual bug (that needed real GBIF data's clustering, not synthetic data -- see Session Notes) |
| test-fetch_inat_occurrences.R | `fetch_inat_occurrences()`, `.inat_observation_count()` | 2026-07-23, **new file**. Mirrors test-check_inat_range.R's mocking strategy (`local_mocked_bindings()` on `.inat_taxon_id()`/`.inat_observation_count()`, then `httr::GET`/`status_code`/`content` for the internal helper directly); 24 tests, fully offline |
| test-get_keys_from_context.R | `get_keys_from_context()`, `.recover_higherrank()` | Mocked rgbif; Session 148 added kingdom-narrowing coverage via a synthetic mixed-kingdom fixture |
| test-make_bbox_wkt.R | `make_bbox_wkt()` | Fully offline |
| test-stack_occurrences.R | `stack_occurrences()` | Fully offline; 2026-07-23 -- dedup-related tests moved to test-dedupe_occurrences.R, since `stack_occurrences()` no longer removes any rows |
| test-dedupe_occurrences.R | `dedupe_occurrences()` | **2026-07-23, new file** -- split out of test-stack_occurrences.R. Fully offline; covers `gbifID` exact match, `collapse_duplicate_occasions` content match (single-source and post-`stack_occurrences()` cases), missing-key-component preservation, `year`/`month`/`day` fallback, custom `taxon_col`/`date_col`/`lat_col`/`lon_col`, and `report_params` attribute refresh |
| test-report_fetch.R | `report_fetch()` | Fully offline |
| test-biotime_fetch.R | `read_biotime_study()` | Fully offline; Session 148 added NA-vs-absent `occurrenceStatus` coverage |
| test-dataone_standardize.R | `fetch_dataone_occurrences()`, `.is_trusted_pasta_url()`, `.download_data_table()`, `.extract_eml_sites()` | Mocked DataONE API; Session 148 added SSRF host-allowlist coverage; 2026-08-08 added `.extract_eml_sites()` coverage (had zero coverage before) for the real embedded-newline site-code regression found by human review, plus a no-newline control case |
| test-dataone_preview.R | `.preview_one_entity()` (guard only) | Session 148, **new file** -- `preview_dataone_occurrences()` itself remains untested, a pre-existing gap |
| test-dataone_taxon_screening_geo.R | `build_taxon_screen_prompt()`, `parse_taxon_screening_response()`, `build_geo_prompt()`, `parse_geo_screening_response()` | LLM mocked |
| test-literature_search.R | `search_literature()`, `download_literature_pdfs()` | OpenAlex calls mocked |
| test-dataone_occurrence_search.R | `.parse_coordinates_field()`, `.parse_pasta_response()`, `.bbox_overlaps()` | **2026-08-08, new file** -- this file (`search_dataone()`, `fetch_dataone_eml()`) had zero test coverage before the human review found real coordinate-parsing bugs. Fully offline; covers the confirmed-real Solr `ENVELOPE(...)` format (degenerate and non-degenerate boxes, case-insensitivity), the legacy `N:`/`S:`/`E:`/`W:` format, the corrected numeric-fallback field order, `.parse_pasta_response()`'s `spatialCoverage/coordinates` XML path with a synthetic fixture matching the real SBC LTER structure it was found against |
| test-pdf_text.R | `.match_header()` | **2026-08-08, new file** -- `pdf_text.R` had zero test coverage before this session. Scoped to the specific bug fixed (numbered two-column-layout headers), not a full file test suite |
| test-pdf_extract.R | `.axis_or_default()`, `.build_axis_instructions()`, `build_pdf_extract_prompt()` | **2026-08-08, new file** -- `pdf_extract.R` had zero test coverage before this session. Scoped to the specific bug fixed (NA-vs-NULL axis defaulting), not a full CSV-parsing/DwC-mapping test suite |
| test-download_gbif_occurrences.R | `download_gbif_occurrences()`, `.gbif_dl_meta_path()` | **2026-09-04**: added orphan-cleanup coverage -- a non-interactive `overwrite = TRUE` re-run (mocked `rgbif::occ_download`/`occ_download_wait`/`occ_download_get`) confirms the old cached zip is removed once the new one lands, plus a cache-size-summary message assertion. The interactive confirmation prompt itself is NOT covered by an automated test -- `interactive()` is a `.Primitive`, confirmed unmockable via `testthat::local_mocked_bindings()`; verify by hand (see `inst/test_overwrite_cache_manual.R`) |
| test-taxafetch_clear_cache.R | `taxafetch_clear_cache()`, `.taxafetch_referenced_zips()` | **2026-09-04, new file**. Fully offline. Covers argument validation, dry-run vs. real deletion, `older_than_days` filtering, `.taxafetch_cache_patterns` matching every real cache file shape (including the `openalex_cache_*.rds` addition), and `orphans_only`'s core behavior (removes only a zip no current `meta.rds` points to; never touches checkpoints/geojson; reports cleanly when nothing is orphaned) |

---

## Key Dependencies

| Package | Role | Note |
|---|---|---|
| TaxaTools | LLM provider functions, taxonomy helpers | Imports |
| httr2 | API calls (PASTA Solr, OpenAlex, Nominatim) | Imports |
| rgbif | GBIF backbone + occurrence download | Suggests |
| CoordinateCleaner | `cc_equ`/`cc_zero`/`cc_gbif` in `filter_gbif_quality()`; `cc_outl()` in `check_geographic_outliers()` | Suggests (2026-07-20). Deliberately not `Imports` -- its own heavy deps (`terra`, `rnaturalearth`) are needed only by the `cc_sea()`/`cc_coun()`/`cc_urb()` functions this ecosystem doesn't use (poor fit for marine eDNA / redundant with existing GBIF-issue-code filtering); the functions actually used here don't need them. |
| data.table | Fast TSV import for `download_gbif_occurrences()` | Suggests |
| dplyr | Data manipulation | Imports |
| stringr | String operations | Imports |
| tibble | Tibble construction | Imports |
| readr | CSV parsing | Imports |
| xml2 | EML XML parsing | Imports |
| rlang | NSE utilities | Imports |
| stats | Internal use | Imports |
| utils | URL encoding etc. | Imports |
| pdftools | `pdf_text()`, `pdf_render_page()` | Suggests (PDF pipeline only) |
| png | `writePNG()` for image encoding | Suggests (PDF pipeline only) |
| base64enc | `base64encode()` for API image blocks | Suggests (PDF pipeline only) |

**Session 134b:** `shiny`/`miniUI`/`leaflet` removed from Suggests -- they were only used
by `define_search_polygon()`, which moved to TaxaTools this session (see Session 134b note
below and TaxaTools/CLAUDE.md).

---

## Session Notes

**2026-07-23, same day, yet another follow-up (Sonnet 5): `dedupe_occurrences()` split out of `stack_occurrences()` -- naming/design critique from the user**

Direct continuation, same day: right after `gbif_snapshot_path` was removed (entry below),
the user raised a naming/architecture concern about `stack_occurrences()` itself, unprompted
by any bug -- a genuine design review, not a bug report. Their point, close to verbatim: the
name "stack_occurrences" implies pure row-combination (possibly even column standardization,
though it never did that), and bundling dedup logic inside a function named "stack" risks a
real failure mode -- a caller with only ONE data source reads the name, reasonably concludes
"stacking" doesn't apply to them, and skips the call (and therefore its dedup) entirely.

**Confirmed this is not hypothetical before doing anything** -- checked the actual documented
GBIF-only pipeline in this file: `get_gbif_occurrences() -> filter_gbif_quality()`, with
`stack_occurrences()` appearing only in the multi-source diagrams. A single-source GBIF
caller following this file's own documented pattern would never call `stack_occurrences()` at
all. **Also confirmed the risk isn't new, or specific to the feature just shipped**: the
pre-existing `gbifID` exact-match dedup (Session 140, not added this session) has the
identical blind spot -- a single `fetch_gbif_occurrences()` call querying multiple
overlapping taxon keys can already produce duplicate `gbifID`s within one un-stacked frame,
before any combination happens. Reported this finding to the user rather than silently
patching only the new feature; they confirmed (via `AskUserQuestion`) that both mechanisms
should move, not just `collapse_duplicate_occasions`.

**Design:** `stack_occurrences()` reverts to a pure combine step -- row-bind + `point_id`
only. Row count is now always exactly the sum of the input frames' row counts, stated
explicitly in the `@return` doc so this invariant is discoverable without reading source. New
`R/dedupe_occurrences.R` (`dedupe_occurrences(data, collapse_duplicate_occasions = TRUE,
taxon_col = "scientificName", date_col = "eventDate", lat_col = "decimalLatitude", lon_col =
"decimalLongitude", coord_precision = 3L)`) takes a single data frame -- stacked or not -- and
runs both checks (moved verbatim, no logic changes: `gbifID` exact match, then
`collapse_duplicate_occasions`'s content-based occasion collapse). Also refreshes a
`report_params` attribute's `n_records` and adds `n_duplicates_removed` when the input
carries one (e.g. from `stack_occurrences()`), so `report_fetch()`'s params list doesn't go
stale after dedup runs.

**Function name chosen via `AskUserQuestion`** (`dedupe_occurrences()` over
`collapse_duplicate_occurrences()`/`clean_occurrences()`) -- direct, matches this package's
existing naming style, unambiguous about what it does regardless of source count (unlike
either alternative, which were either more verbose or vaguer about scope).

**Every real call site across the monorepo found via grep and updated** (not left as a
silent regression) -- this was the necessary consequence of moving the pre-existing `gbifID`
dedup, which every real caller of `stack_occurrences()` got "for free" and automatically
before this change:
- `TaxaExpect::build_priors()` (`R/build_priors.R`) -- real package code, not a demo script.
  `dedupe_occurrences()` now runs unconditionally after the `point_id`-ensure block,
  regardless of whether `supplemental_occurrences` was supplied/stacked, matching the
  "single source still needs dedup" principle this whole change is about.
- `TaxaAssign/inst/workflows/camera_trap_posterior_workflow.R`,
  `TaxaExpect/inst/workflows/generate_priors_workflow.R`,
  `inst/TaxaID_Workflow_Template_TEST.R` (the root master template),
  `TaxaFetch/inst/Merge_sources_workflow.R`, `TaxaFetch/inst/pdf_workflow_test_v4.R`,
  `TaxaFetch/inst/biotime_workflow.R`, `TaxaFetch/inst/workflows/fetch_occurrences_workflow.R`
  (the Layer-1 teaching script, both Variant A active code and Variant B's commented
  template) -- all gained an explicit `dedupe_occurrences()` call immediately after their
  `stack_occurrences()` call, including the single-source cases (`fetch_occurrences_workflow.R`
  Variant A is exactly the single-GBIF-source case this whole redesign targets).
  `Merge_sources_workflow.R`'s own header comments and the "if you only have GBIF data, skip
  to Step 2" note (the literal advice that would have told a reader to skip dedup) rewritten
  to state the new requirement directly.
- `TaxaFetch/vignettes/data-acquisition.Rmd` and `TaxaFetch/inst/review_function_inputs.R`
  (the dev-utility script exercising every exported function's inputs offline) both updated
  for consistency and documentation accuracy, even though neither is a live production
  pipeline.
- `TaxaHabitat/inst/workflows/assign_habitat_workflow.R` and
  `TaxaFetch/inst/dataone_quickstart.R` checked and left alone -- both only *mention*
  `stack_occurrences()` in prose/comments, neither has a real call site.

**Testing:** `test-stack_occurrences.R`'s dedup-specific tests (gbifID exact match,
`collapse_duplicate_occasions` content match, missing-key-component preservation,
`year`/`month`/`day` fallback, custom `taxon_col`/`date_col`, `collapse_duplicate_occasions =
FALSE`) moved into new `test-dedupe_occurrences.R` and adapted to call `dedupe_occurrences()`
directly -- some exercising it on a single, unstacked frame specifically (the scenario this
whole redesign is about), others on a `stack_occurrences()`-combined frame first (the
cross-source case). `test-stack_occurrences.R` itself now only covers pure combination
behavior; its old gbifID test renamed to assert `stack_occurrences()` does NOT dedupe (a
direct regression guard for the split itself). Two new tests added for the `report_params`
refresh behavior. `devtools::test()` 0 failures, `devtools::check()` 0 errors/0 warnings/1
note (pre-existing clock-check artifact) -- see this file's top session note for exact counts.

**2026-07-23, same day, immediate follow-up (Sonnet 5): `fetch_dataone_occurrences(gbif_snapshot_path=)` removed -- superseded by `stack_occurrences()`'s new dedup**

Direct continuation of the entry immediately below: right after shipping
`collapse_duplicate_occasions`, the user asked whether it makes any *existing* dedup
redundant. Worked through both candidates explicitly rather than guessing:

- **`gbifID` step (Session 140): NOT redundant, kept as-is.** It catches an exact-duplicate
  GBIF record whose `scientificName`/`eventDate` happen to be `NA` -- `collapse_duplicate_
  occasions` deliberately never drops a row with an incomplete key, so it would miss exactly
  this case. The two steps cover different failure modes.
- **`fetch_dataone_occurrences(gbif_snapshot_path=)`'s own dedup (`.load_gbif_hashes()`/
  `.deduplicate_against_gbif()`): redundant, removed.** Same key formula
  (`tolower(scientificName)|eventDate|round(lat,3)|round(lon,3)`), but for the realistic
  combined pipeline (fetch GBIF + fetch DataONE + `stack_occurrences()`), the new step now
  does the identical cross-check automatically on the in-memory data. Two things pushed this
  past "overlapping" to "remove it": (1) grepped the whole monorepo -- **zero real callers**
  ever passed `gbif_snapshot_path`, the same "no external users" bar already used to remove
  `fetch_reference_sequences()`/`expand_consensus_candidates()`/`read_wildlife_insights_
  output()`; (2) it was actually the *weaker* of the two mechanisms -- `.load_gbif_hashes()`/
  `.deduplicate_against_gbif()` coalesced a missing name/date to `""` and missing lat/lon to
  `0` before hashing, so two incomplete records could spuriously collide, the opposite of
  `collapse_duplicate_occasions`'s deliberate never-match-on-incomplete-data design. The one
  thing it covered that the new step can't -- deduping against an external GBIF snapshot file
  not otherwise fetched live in the same session -- had no real caller exercising it either.

User confirmed full removal (not merely documenting the overlap, and not fixing the coalesce
gap in place, both offered as alternatives). Removed: `gbif_snapshot_path` param on
`fetch_dataone_occurrences()`; `gbif_hashes` threaded through `.process_one_dataset()` /
`.finalize_entity()` / `.attempt_odm_join()` (5 internal call sites across the file, including
two recursive `.finalize_entity()` calls from the DwC-Archive-join and ODM-join branches);
`.load_gbif_hashes()` and `.deduplicate_against_gbif()` themselves deleted entirely. Roxygen
`@details`/`@examples` on `fetch_dataone_occurrences()` rewritten to point at
`stack_occurrences()`'s `collapse_duplicate_occasions` instead of describing a mechanism that
no longer exists. Now-unused `dplyr::coalesce`/`readr::read_tsv` `@importFrom` entries dropped
from this file's own roxygen (confirmed via grep neither is called anywhere else in
`dataone_standardize.R`; `read_tsv` is still used, namespaced, in `download_gbif_occurrences.R`
-- unaffected). 11 internal-helper test call sites in `test-dataone_standardize.R` (all
`.attempt_odm_join()` tests) had their now-invalid `gbif_hashes = NULL` argument removed; no
dedicated tests existed for the two deleted helpers themselves, since they were never
`@export`ed. Also fixed a now-stale cross-reference in `inst/PDF_PIPELINE_DATAONE_PARALLEL.md`
that named the removed parameter directly.

`devtools::test()` 0 failures (553, up from 549 -- net +4 despite removing 11 arguments, since
none of those were separate expectations), `devtools::check()` 0 errors/0 warnings/1 note (the
same pre-existing "unable to verify current time" clock-check artifact). Not yet re-verified
against a real DataONE fetch (no real caller ever used the removed parameter, so no real
workflow needed updating either).

**2026-07-23, continued yet further (Sonnet 5): `stack_occurrences()` gains `collapse_duplicate_occasions` -- redundant citizen-science reports vs. TaxaExpect's occupancy semantics**

Branch not tracked. Prompted by a user question about whether TaxaFetch already removes
redundant occurrence records, which led to a design discussion rather than a quick lookup:
the existing `gbifID` dedup (Session 140) only catches the *identical* GBIF record entering
twice (an exact-ID match), and `fetch_dataone_occurrences(gbif_snapshot_path=)`'s content-based
dedup only compares DataONE against a manually-supplied GBIF snapshot -- neither runs
automatically when combining sources in `stack_occurrences()` itself, and neither catches the
scenario the user actually raised: a rare-bird alert drawing dozens of independent eBird
checklists for one individual, or a bioblitz producing a dozen independent iNaturalist uploads
of one local population. Each of those is a genuinely distinct GBIF record (different
`gbifID`, different `occurrenceID`, often a different underlying dataset/publisher entirely)
-- so the existing dedup step is structurally blind to it -- but is not a distinct detection
**occasion**.

**The key reframe, from the user:** the right question for this ecosystem's occupancy-style
priors isn't "how many people documented a species" but "was the species documented, per
number of documentations" -- i.e. the unit of evidence should be the detection occasion
(species x site x date), not the report. This is standard occupancy-modeling semantics
(MacKenzie-style detection histories are built per site-visit, not per observer), and it
reframes what looked like a weakness of a naive content-based dedup (it could wrongly collapse
two people independently photographing two different individuals of a common species at the
same rounded location on the same day) into the actual intent: occupancy modeling doesn't care
about individual count, only presence, so collapsing multiple simultaneous reports of a
detection down to one row is correct, not lossy.

**Verified against the real downstream consumer before implementing, per the user's explicit
request ("check TaxaExpect first, then implement it")** -- rather than assuming the occupancy
framing was actually load-bearing anywhere: read `TaxaExpect::prepare_model_dataframe()`
directly (`R/prepare_model_dataframe.R`). Confirmed `n_species` (the binomial numerator for a
taxon at a site) and `n_total_at_site` (the shared effort denominator across every taxon at
that site) are both literal `dplyr::n()` **raw record counts** -- not presence/absence
indicators. This means the redundant-report problem is not hypothetical or only a modeling
nicety: an uncollapsed burst of duplicate reports for one species inflates that species'
`n_species` directly (and dilutes every other species' apparent frequency slightly, since
`n_total_at_site` sums across all taxa at the site) -- a real, mechanistic distortion of
TaxaExpect's actual model inputs, not just redundant bookkeeping.

**Implementation** (`R/stack_occurrences.R`): new `collapse_duplicate_occasions` param,
default `TRUE` (not opt-in -- confirmed with the user this is the correct default given what
TaxaExpect actually consumes, not assumed). Collapses rows sharing an identical combination of
`taxon_col` (default `"scientificName"`, case-insensitive/trimmed) x `date_col` (default
`"eventDate"`, falling back to a constructed `"YYYY-MM-DD"` from `year`/`month`/`day` when
`eventDate` is absent -- needed because `get_gbif_occurrences()`'s `"standard"` column set
carries `year`/`month`/`day` but not `eventDate` itself) x `lat_col`/`lon_col` rounded to
`coord_precision` (default `3`, reusing the exact key formula already validated in
`fetch_dataone_occurrences(gbif_snapshot_path=)`'s cross-source dedup:
`tolower(scientificName)|eventDate|round(lat,3)|round(lon,3)`). Confirmed via a source check
that every current TaxaFetch source (GBIF, DataONE, BioTime, literature/PDF) already emits
`scientificName`/`eventDate` under those exact names, so the defaults need no per-source
override in practice.

Deliberately content-based, not exact-ID like the `gbifID` step: a row missing any key
component (no taxon, no date and no year/month/day, or either coordinate) is always kept,
never dropped on incomplete information -- this can only produce false negatives (a real
duplicate occasion missed, e.g. differing date precision across platforms), never false
positives, since two records agreeing on species/date/location to ~100 m are extremely
unlikely to be genuinely independent occasions. Silent no-op when `taxon_col`/`date_col`
aren't present at all in the combined frame, matching the `gbifID` step's own established
convention (no "column not found" message noise on every call) -- confirmed this doesn't
regress any pre-existing test, since none of the existing fixtures carry an `eventDate`/
`year`/`month`/`day` column at all. `collapse_duplicate_occasions = FALSE` is the escape
hatch for a caller who deliberately wants raw report-level/reporting-volume data instead of
TaxaExpect's occupancy framing.

9 new tests in `test-stack_occurrences.R`: cross-platform collapse (different
`occurrenceID`/dataset, same occasion, case-insensitive taxon match), genuinely distinct
dates/species/locations never collapsed, rows missing a key component always kept, the
`year`/`month`/`day` fallback (GBIF standard-column shape), `collapse_duplicate_occasions =
FALSE` preserving every raw report, silent no-op with no taxon/date columns present, and
custom `taxon_col`/`date_col` overrides. `devtools::test()` 0 failures (549, up from 539),
`devtools::check()` 0 errors/0 warnings/1 note (pre-existing "unable to verify current time"
clock-check artifact, unrelated). Cross-referenced in `TaxaFetch/R/get_gbif_occurrences.R`'s
own `@details` (the GBIF-as-aggregator rationale added earlier this session) and
`TaxaExpect::prepare_model_dataframe()` via `@seealso`, so a future reader lands on the
mechanistic reason directly rather than just the mechanism. Not yet propagated to any real
production workflow script (Mugu/PtConception, outside this monorepo) -- those already call
`stack_occurrences()` with no override, so they pick up the new default behavior
automatically the next time they're run with a reinstalled package, but this was not
separately verified against real multi-platform GBIF data this session.

**2026-07-23, continued (Sonnet 5): `filter_gbif_quality()` redesigned around a full removal audit trail**

Branch not tracked. Direct continuation: after the `cc_cen()`/`cc_cap()`/`cc_inst()` work
below, the user ran the real Mugu data and noticed no new output columns from the three new
checks, asking whether they'd actually run. Answer: yes, but `filter_gbif_quality()` (like
every filter before it) just silently drops rows -- no annotation, ever, for any of its nine
steps. The user's follow-up reframed this as a real gap, not just a one-off question: seeing
*which* records got removed and *why* would let a user re-assess/repair mistaken exclusions,
double as raw material for reporting genuine GBIF data-quality problems back to GBIF, and
make two users' differing filter arguments produce comparable results instead of silently
different ones. Scoped initially to just the `CoordinateCleaner` step, then explicitly
widened by the user to cover all nine filters.

- **Design:** `attr(result, "removed_records")` -- always present (a data frame, possibly
  zero rows, never `NULL`), one row per removed record, every original column preserved
  (`gbifID`/`datasetKey` included, specifically for the "report it to GBIF" use case) plus a
  new `filter_reason` column. Most steps get a single fixed reason string
  (`"missing_coordinates"`, `"absent_occurrence"`, `"basis_of_record"`,
  `"coordinate_uncertainty"`, `"coordinate_decimal_precision"`, `"edna_keyword"`,
  `"no_species_id"`). Two steps get richer, per-row detail because the fixed string alone
  would lose real information: the GBIF issue-code filter reports the SPECIFIC `bad_issues`
  code that matched (`"flagged_issue_code:COORDINATE_OUT_OF_RANGE"`, not just that some code
  did -- a record's `issues` field can contain codes outside `bad_issues` too, so this
  disambiguates); the `CoordinateCleaner` step reports every check that flagged a given
  record, joined with `;` (`"equal_coordinates;near_zero"`), since several checks run
  against the same surviving data and a record can fail more than one at once -- verified
  with a real constructed case, `(0.01, 0.01)`, which is simultaneously an equal-coordinate
  record AND near `(0,0)`.
- **Return contract unchanged:** `filter_gbif_quality()` still returns just the cleaned data
  frame, exactly as every existing caller already expects -- `removed_records` is purely
  additive via `attr()`, not a second return value, so nothing downstream needs to change to
  keep working.
- **Internals fully rewritten**, not just extended: every step now computes an explicit
  `keep` logical mask instead of piping through `dplyr::filter()`, since capturing the
  removed rows needs that mask directly. This incidentally fixed a real, pre-existing bug
  found but deliberately left alone on 2026-07-20 (out of scope at the time): steps 7
  (eDNA) and 8 (species-level requirement) never reassigned the `n_current` tracking
  variable after removing rows, so the printed "Removed N records" message could overcount
  if both steps removed rows in the same call (comparing against a stale pre-step-6 count).
  The new mask-based counting (`sum(!keep)` at each step, computed fresh) has no equivalent
  staleness to inherit -- fixed as a natural side effect of the rewrite, not a separate patch.
- **A real bug caught in my own first draft, before it shipped:** the `CoordinateCleaner`
  step's summary message split a single format string across multiple `sprintf()`
  arguments -- exactly the "split-string sprintf" footgun already documented in this file's
  own Known Footguns section (`sprintf()` does not concatenate multiple string arguments;
  only the first is used as the format, the rest are silently treated as substitution
  values). Caught by re-reading my own diff rather than trusting it compiled cleanly; fixed
  with `paste0()` before `sprintf()`, matching every other multi-line message already in
  this function.
- **Testing:** all 50 pre-existing tests pass unchanged against the rewritten internals
  (confirms behavioral equivalence, not just "it runs"). 5 new tests added for
  `removed_records` itself: always-present-with-0-rows, a simple missing-coordinates case,
  the specific-matched-issue-code case, the real double-simultaneous-`CoordinateCleaner`-
  reason case, and original-column preservation (`gbifID`/`datasetKey`).
- **Performance re-verified, not assumed, given the internals changed substantially:**
  re-benchmarked at Mugu's real 132k-row scale, this time under a deliberately harsh
  synthetic ~80%-removal stress test (far worse than real GBIF data -- the actual Mugu run
  removed ~7.5%) -- 11.7s, up from the earlier zero-removal benchmark's 1.37s. A real,
  expected cost (each step now subsets both kept and removed rows, not just kept once), not
  a concern for a function that isn't in a hot loop.
- `devtools::test()` 0 failures (506, up from 494), `devtools::check()` 0/0/0. Reinstalled
  to `~/Library/R/4.0/library`.

**2026-07-23 (Sonnet 5): deferred `cc_cen()`/`cc_cap()`/`cc_inst()` checks added; `check_geographic_outliers()` wired into PtConception**

Branch not tracked. Two pieces of work, both direct continuations of the 2026-07-20 design/
debugging thread above, picked up after the user confirmed both real bugs fixed and the
mechanism working end to end on real Mugu data.

- **`cc_cen()`/`cc_cap()`/`cc_inst()` added to `filter_gbif_quality()`** -- the "Tier 2"
  checks deferred from the original design conversation specifically because they need
  reference data (country/province centroids, national capitals, ~10,000 biodiversity
  institution locations) rather than being trivially self-contained like `cc_equ`/`cc_zero`/
  `cc_gbif`. Verified via direct source inspection (`deparse(body(cc_cen))` etc., not the
  docs alone) that all three resolve their own `ref = NULL` default to `CoordinateCleaner`'s
  bundled `countryref`/`institutions` data objects automatically -- no download, no network
  call, matching `cc_outl()`'s own already-established self-contained behavior. Also
  confirmed these three do NOT share `cc_outl()`'s record-count-triggered raster-
  approximation risk (the bug fixed 2026-07-20): they're plain per-row point-in-buffer tests
  against a fixed external reference set, with no species grouping or record-count branching
  in their source at all. New params `exclude_country_centroid`/`exclude_capital`/
  `exclude_institution`, each default `TRUE`, called with only `lon`/`lat`/`value` supplied
  (same "don't hand-copy the package's own defaults" principle already applied to
  `cc_equ`/`cc_zero`/`cc_gbif`) -- avoids re-running into the earlier problem where an
  attempt to replicate `cc_zero()`'s/`cc_gbif()`'s exact buffer values hit conflicting
  numbers across sources.
- **Performance verified before shipping, not assumed:** benchmarked `filter_gbif_quality()`
  with all six `CoordinateCleaner` checks against a synthetic ~122,000-row dataset (matching
  Mugu's real scale) -- 1.37 seconds. Confirms the reference-data-cropped-to-bbox design
  keeps cost independent of row count, same reasoning already used to conclude no analogous
  batching bug exists here.
- **New tests use REAL reference coordinates, not guessed ones**: each test pulls an actual
  row directly from `CoordinateCleaner::countryref`/`institutions` at test-run time (e.g.
  `CoordinateCleaner::countryref[CoordinateCleaner::countryref$type == "country", ][1, ]`)
  rather than hand-typing a coordinate believed to be close enough -- guarantees correctness
  regardless of the package's exact buffer defaults, the same lesson learned the hard way
  with `cc_zero()`/`cc_gbif()` on 2026-07-20. All pre-existing fixtures (Southern California
  test coordinates, none near a real centroid/capital/institution) still pass unchanged with
  the new checks on by default -- confirms no coincidental overlap.
- **`check_geographic_outliers()` wired into all three real, actively-maintained PtConception
  workflow scripts** (outside this monorepo, not under git, at
  `~/My Drive/Rscripts/eDNA/PtConception/`): `PtConceptionWorkflow_12S_single_site.R`,
  `PtConceptionWorkflow_18S_2_single_site.R`, `PtConceptionWorkflow_12S_multi_site.R` -- the
  identical pattern already validated end-to-end on both real Mugu workflows (new
  `CACHE_DIR_GBIF_GLOBAL` constant, a `..._geo_outlier_check.rds` checkpoint using each
  file's own existing `file.exists()` caching convention, outlier-status-based row removal
  immediately after `filter_gbif_quality()`). All three PtConception scripts share the same
  `OUT_DIR`, so `CACHE_DIR_GBIF_GLOBAL` is shared across them too -- safe, since
  `fetch_gbif_occurrences()`'s own checkpoint filenames are signature-based (keyed on the
  exact species-key set, not just the directory), and sharing lets sibling scripts targeting
  the same study region reuse each other's global-species fetches. Two other PtConception
  scripts checked and deliberately left untouched: `PtConceptionWorkflow_12S_test_genus_fix.R`
  doesn't call `filter_gbif_quality()` at all (not relevant); `TaxaID_eDNA_Workflow_Template.R`
  does, but reads as a template/scaffold script rather than one of the real per-study
  production workflows -- flagged for the user's own call, not touched.
- All three edited PtConception files parse cleanly (`parse(file = ...)`, no execution --
  these require real GBIF/LLM API calls and would overwrite real checkpoints, so live-running
  them is the user's call, same as the Mugu wiring). **Not yet run against real PtConception
  data.**
- `devtools::test()` 0 failures (494, up from 487), `devtools::check()` 0/0/0. Reinstalled to
  `~/Library/R/4.0/library`.

**2026-07-20, continued yet further (Sonnet 5): `fetch_gbif_occurrences()` checkpoint bug -- found via a real GBIF timeout**

Branch not tracked. Direct continuation: after the `cc_outl()` per-species fix (below), the
user re-verified it against the real Mugu data with a targeted re-run
(`raw_gbif %>% filter_gbif_quality(...) %>% check_geographic_outliers(cache_dir =
CACHE_DIR_GBIF_GLOBAL)`). That run hit a real GBIF API timeout on key 43 of 51
(`Timeout was reached [api.gbif.org]: Operation too slow`) -- an external, environmental
failure, not a code bug. But the resulting error message was: `"fetch_gbif_occurrences:
fetch aborted early.\n  Enable cache_dir for resumable fetches."`, even though the user HAD
passed `cache_dir = CACHE_DIR_GBIF_GLOBAL`.

- **Root cause, found by re-reading `fetch_gbif_occurrences()`'s chunk loop directly:** with
  51 keys and the default `chunk_size = 20`, chunks are `[1-20]`, `[21-40]`, `[41-51]` (11
  keys); key 43 is the 3rd key of the 3rd chunk. `global_pos <- global_pos + length(chunk_keys)`
  ran unconditionally, BEFORE the abort check -- so on this chunk's abort, `global_pos` jumped
  from 40 to `40 + 11 = 51`, exactly `length(keys)`. The abort branch's own resumability check
  (`global_pos < length(keys)`) then evaluated `FALSE`, routing to the generic "enable
  cache_dir" message instead of the "progress saved" one, even though a real checkpoint HAD
  already been written after chunk 2 completed (`global_pos = 40 < 51` was true then).
- **A more serious problem than the misleading message, found by tracing the logic further:**
  the same `global_pos`-after-full-chunk computation is ALSO used to build the checkpoint's own
  `remaining_keys` (`keys[(global_pos + 1L):length(keys)]`) in the branch where a checkpoint
  IS saved. Using a post-chunk `global_pos` there means `remaining_keys` always starts AFTER
  the whole aborting chunk -- silently excluding the specific key that failed, and any others
  queued after it in that same chunk, from `remaining_keys` entirely. On resume, that key would
  never be retried again. This directly contradicts the function's own documented design
  ("Any exhausted retry aborts immediately (no silent skipping)") -- the abort itself wasn't
  silent, but a retried key being permanently dropped from the retry set would have been.
- **Fix:** moved the abort check to run BEFORE `global_pos` advances past the aborting chunk,
  so checkpoint computations always use the position from the START of that chunk. The whole
  aborting chunk (not just the failed key onward) is included in `remaining_keys` on resume,
  deliberately discarding any of that chunk's own partial success (e.g. key 3 succeeding before
  key 4 failed) in favor of a clean re-fetch -- avoids any risk of duplicate rows from a key
  that both partially succeeded pre-abort and gets refetched.
- **New regression test** (`test-fetch_gbif_occurrences.R`): 5 keys, `chunk_size = 2`, key 4
  (2nd key of the 2nd chunk, after key 3 succeeds within the same chunk) mocked to fail --
  asserts the saved checkpoint's `remaining_keys` includes key 4 itself (it didn't, under the
  old logic) and, per the fix's own re-fetch-whole-chunk design, keys 3-5 together.
- **Practical note for the user's own blocked run:** no action needed for the checkpoint file
  from the actual failed run specifically -- that abort happened to land right after chunk 2's
  real checkpoint save, so simply re-running the same `fetch_gbif_occurrences()`/
  `check_geographic_outliers()` call resumes from key 41 rather than restarting. The fix
  matters for the general case (e.g. a timeout in the very FIRST chunk of a run, before any
  prior chunk had a chance to checkpoint, which the old logic could have silently mishandled).
- `devtools::test()` 0 failures (487, up from 483), `devtools::check()` 0/0/0. Reinstalled to
  `~/Library/R/4.0/library`.

**2026-07-20, continued (Sonnet 5): real production bug found on `check_geographic_outliers()`'s first live run**

Branch not tracked. Direct continuation of the same-day work below: the function was wired
into `MuguFishWorkflow.R`/`MuguWilderFishWorkflow.R` (outside this monorepo, not under git)
and run for real against the full Mugu dataset -- the very first live test. The user's own
result was the tell: `Pseudotolithus epipercus` -- the exact motivating case for this whole
mechanism (an African species with one errant citizen-science record in La Jolla) -- came
back `outlier_status = "consistent"`, not `"outlier"`. The literal case the function exists
to catch wasn't caught, on the first real run.

- **Two hypotheses tested and refuted before finding the real cause**, both live-verified
  with actual R code rather than asserted: (1) a `gbifID` type mismatch between
  `download_gbif_occurrences()`'s output (`bit64::integer64`, via `data.table::fread()`
  inferring the type for GBIF IDs exceeding 32-bit range) and `fetch_gbif_occurrences()`'s
  output (plain character, via `rgbif`) -- tested directly with a realistic reproduction
  (`fread()`-typed `integer64` vector subset via a logical mask, `match()`ed against a
  character vector, at the real scale); `match()` correctly coerces and finds every match
  even with `bit64` never explicitly attached (`MuguFishWorkflow.R` doesn't `library(bit64)`).
  Not the bug. (2) A species-crossing distance computation in `cc_outl()` (i.e. the "distance"
  method comparing across species when other rare species have geographically nearby points)
  -- tested with a synthetic "decoy species" reproduction placing points near California
  alongside the real 12-point *P. epipercus* global cloud; `cc_outl()` correctly restricted
  distance comparisons to same-species pairs regardless. Not the bug.
- **The user's own diagnostic re-run of the real, full batch surfaced the actual cause
  directly**: `Warning message: ... Using raster approximation.` Read `cc_outl()`'s own
  source (`print(CoordinateCleaner::cc_outl)`) rather than guessing further --
  `record_numbers <- unlist(lapply(splist, nrow)); if (any(record_numbers >= 10000) |
  thinning) { warning("Using raster approximation."); ras <- ras_create(...) }` -- confirmed
  this check is scoped to the WHOLE call (`any()` across every species' `splist` entry), not
  per species. `check_geographic_outliers()` batches every locally-rare species into one
  `cc_outl()` call for fetch efficiency; the real Mugu batch was 51 species / 193,458 total
  records, meaning at least one locally-rare-but-globally-common species pushed the whole
  call onto the coarser raster path, degrading precision for every other species sharing the
  call -- including the sparse, obviously-isolated *P. epipercus* data.
- **Fix verified two ways before shipping:** (1) direct source reading confirmed the
  mechanism unambiguously; (2) a synthetic reproduction (the real 12-point *P. epipercus*
  cloud plus a synthetic 10,500-row uniform-random "common species") confirmed the warning
  genuinely fires in a batched call of this shape -- though this particular synthetic
  "common species" wasn't extreme enough to flip the final flag from `FALSE` to `TRUE`,
  meaning the real failure depends on the actual clustered shape of real GBIF data in a way
  a quick synthetic test couldn't fully reproduce. Shipped the fix anyway on the strength of
  the source-level mechanism plus the real production evidence, rather than insisting on a
  synthetic repro of the exact wrong-answer case -- the per-species-call design is strictly
  more conservative regardless (a species-crossing raster decision has no legitimate reason
  to exist in this function at all).
- **Fix:** `CoordinateCleaner::cc_outl()` now called once PER SPECIES (looping over
  `unique(global_occ$species)`) instead of once for the combined batch, so the raster-mode
  decision is scoped to each species' own record count -- exactly where `cc_outl()`'s own
  design intends it. R-level loop overhead is negligible next to the GBIF fetch itself.
- **New regression test** (`test-check_geographic_outliers.R`) mocks
  `CoordinateCleaner::cc_outl()` directly and asserts it receives exactly one species per
  call -- encodes the fix permanently without needing a slow, hard-to-construct 10,000+ row
  fixture to reproduce the raster branch itself. The original test suite (max ~17 rows
  across all fixtures) never exercised this code path at all -- clean `devtools::test()`
  gave false confidence, the same "check dataset scale before trusting synthetic tests
  generalize" lesson this ecosystem has hit before with `restore_suppressed_candidates()`
  (see `[[project_restore_suppressed_candidates_implementation]]` in the memory system) --
  worth remembering as a recurring pattern, not a one-off.
- `devtools::test()` 0 failures (483, up from 481), `devtools::check()` 0/0/0. Reinstalled to
  `~/Library/R/4.0/library`. Not yet re-run end-to-end against the real full Mugu dataset with
  the fix in place -- left for the user, since it involves real GBIF API calls and would
  overwrite the real `_geo_outlier_check.rds` checkpoint (delete it first, or it'll load the
  stale pre-fix result via the workflow's own `.use_cache()` gate).

**2026-07-20 (Sonnet 5): `check_geographic_outliers()` -- geographic-outlier detection for rare-in-bbox species**

Branch not tracked (no git repo at the monorepo root in this session's environment).
Prompted by the user's real Mugu edge case (*Pseudotolithus epipercus*, an African species
with a single errant citizen-science observation in La Jolla, `COORDINATE_REPROJECTION_
SUSPICIOUS`/`CONTINENT_DERIVED_FROM_COORDINATES`/`TAXON_ID_NOT_FOUND` in its `issues` field)
asking for a *generic* fix, not a fix for that one species -- see
`[[project_edge_case_error_taxa_design]]` in the memory system for the fuller design
conversation this implements.

- **Design arc, briefly:** considered (1) trusting GBIF's own `issues` quality flags more --
  rejected as weak/non-generalizing, those three codes describe GBIF's own geoprocessing
  history, not species-range plausibility; (2) `TaxaFetch::check_inat_range()`
  (point-in-polygon against iNaturalist's range model) -- real and reusable, but its own
  documented caveat (false negatives common for aquatic/marine taxa given low iNat observer
  effort there) makes it a poor primary signal for this ecosystem's dominant 12S/18S fish
  eDNA use case; kept as a secondary/fallback idea, not built this session; (3) a
  self-referential geographic-outlier test -- the one built. Initially scoped as "does this
  species' own already-fetched occurrence cloud contain an isolated point," but the user
  corrected the premise: `get_gbif_occurrences()`'s search is always bbox-scoped, so a local
  pull never contains the wider distribution needed to test against, and a *global*
  distance-matrix package like `CoordinateCleaner` fetching worldwide data for every
  candidate species would be needlessly expensive. Real fix: gate the (expensive) global
  fetch to only species with few *local* (bbox) records -- exactly the "singleton in our
  bounding box" case the user meant by "suspicious of singletons," not a global-record-count
  reading.
- **`CoordinateCleaner` adoption, narrowed twice:** first considered hand-rolling
  `cc_outl()`'s logic to avoid the package's `terra`/`rnaturalearth` dependency weight; a full
  function-by-function inventory (sourced from the live CRAN reference manual, not memory)
  showed those two heavy deps are needed only by `cc_sea()`/`cc_coun()`/`cc_urb()` -- exactly
  the functions that don't fit this ecosystem (marine-hostile, or redundant with
  `COUNTRY_COORDINATE_MISMATCH` already in `filter_gbif_quality()`'s `bad_issues`) -- while
  the useful functions (`cc_outl`, `cc_equ`, `cc_zero`, `cc_gbif`, plus `cc_cen`/`cc_cap`/
  `cc_inst` for a possible future session) either need no reference data or only the
  package's own small bundled tables. `Suggests`-gated the whole package rather than hand-roll
  anything. Second correction, same session: an attempt to hand-replicate `cc_zero()`'s/
  `cc_gbif()`'s buffer defaults for `filter_gbif_quality()`'s new checks hit genuinely
  conflicting numbers across sources (and a fabricated-looking GBIF-HQ coordinate from a web
  search) -- since `CoordinateCleaner` was already an accepted `Suggests` dependency for
  `cc_outl()`, there was no remaining reason to reimplement three more functions with
  constants that couldn't be verified; switched to calling `cc_equ()`/`cc_zero()`/`cc_gbif()`
  directly, using the package's own internal defaults.
- **`fetch_gbif_occurrences(geometry = NULL)`:** required for the global re-fetch step;
  confirmed via direct code read (not assumed) that this was NOT previously supported --
  `geometry` had a hard `is.character()`/length-1 validation with no `NULL` path,  even
  though the underlying `rgbif::occ_data()` call natively supports an unrestricted search.
  Relaxed the check; found and fixed a real latent bug in the same area while there --
  `.gbif_checkpoint_path()`'s `nchar(geometry)` would have returned `integer(0)` for `NULL`
  geometry, breaking its `sprintf("%d", ...)` checkpoint-filename signature on the very first
  call. `get_gbif_occurrences()` needed no change -- it has no geometry validation of its own
  and just forwards the value through.
- **`check_geographic_outliers()` (new function, `R/check_geographic_outliers.R`):** tallies
  local (bbox) record counts per species; for species below `min_local_n` (default `5L`),
  fetches that species' global distribution via `fetch_gbif_occurrences(geometry = NULL)`
  (all rare species batched into one call, reusing that function's existing chunking/retry/
  checkpoint machinery) and runs `CoordinateCleaner::cc_outl(method = "distance", tdi = 1000)`
  against the combined cloud. Adds `local_n`/`global_n_unique`/`outlier_status` columns.
  `outlier_status` is deliberately 4-valued, never a bare logical --
  `"not_tested_sufficient_local_data"` / `"insufficient_global_data"` / `"outlier"` /
  `"consistent"` -- mirroring `check_inat_range()`'s `range_status` convention, so "we
  couldn't check" is never silently folded into "we checked and it's fine." `min_occs`
  (default `7L`, matching `cc_outl()`'s own default) is re-checked explicitly against the
  real global count rather than trusted to `cc_outl()`'s own silent-pass-below-threshold
  behavior; that function's own console warning about it is suppressed (`suppressWarnings()`)
  since it's redundant with the structured status column this function already returns.
- **Testing:** all three changes covered offline. `test-fetch_gbif_occurrences.R` gained a
  `geometry = NULL` case (mocked `rgbif::occ_data`, asserts the captured argument is
  genuinely `NULL`) and a direct `.gbif_checkpoint_path()` unit test. `test-filter_gbif_
  quality.R` gained real (not mocked) `CoordinateCleaner` calls for the equal-coordinate and
  near-zero cases, `skip_if_not_installed`-guarded, plus the standard missing-package
  skip-with-message test mirroring the existing `rgbif` pattern. New `test-check_geographic_
  outliers.R` mocks only `rgbif::occ_data` (the network boundary) so the real
  `fetch_gbif_occurrences()` and real `CoordinateCleaner::cc_outl()` both run underneath --
  genuine coverage of all three `outlier_status` outcomes (an isolated point flagged, a
  too-sparse species correctly reported as untested rather than silently passed, a point
  inside its real cluster left alone), not just the plumbing between them.
  `CoordinateCleaner` (3.0.1) installed and verified loadable before running any of this.
  `devtools::document()`/`test()`/`check()` all clean: 481 expectations (up from 459), 0
  failures; 0 errors/0 warnings/0 notes. Reinstalled to `~/Library/R/4.0/library`.
- **Real call-site impact:** `filter_gbif_quality()`'s three new checks default `TRUE`, so
  every existing in-repo caller (`TaxaExpect::build_priors()`, `TaxaExpect/inst/workflows/
  generate_priors_workflow.R`, `TaxaAssign/inst/workflows/camera_trap_posterior_workflow.R`,
  `TaxaWizard/inst/graph/snippets/taxa_to_occ.R`) now applies them automatically wherever
  `CoordinateCleaner` happens to be installed -- a behavioral default change, not just an
  addition; logged in `TaxaID/CLAUDE.md`'s breaking-changes table. `check_geographic_
  outliers()` itself is new and not yet wired into any production workflow (PtConception/
  Mugu, outside this monorepo) -- that rollout, plus a possible follow-on session adding
  `cc_cen()`/`cc_cap()`/`cc_inst()` (country-centroid/capital/biodiversity-institution
  proximity checks, scoped but not built this session), are both left open.
- **Found, not fixed (pre-existing, out of scope):** `filter_gbif_quality()`'s steps 7
  (eDNA) and 8 (species-level requirement) never reassign `n_current` after removing rows,
  so if both steps remove rows in the same call, step 8's printed "Removed N records" message
  can overcount by including step 7's removals too. Cosmetic (affects only the informational
  message, not the actual filtering result or `data` itself) and pre-existing, not touched
  by this session's own step 9, which computes its own accurate before/after count instead
  of relying on the stale variable.

**Session 148 (2026-07-09): full code + domain review (`inst/Code and Domain Review 2.Rmd`)**

Branch `main`. Full pass-by-pass code and domain review, findings and fixes recorded in
`taxafetch_review.Rmd` at the TaxaID root (following the `taxatools_review.Rmd`/
`taxatools_review_response.md` precedent, combined into one document since review and
fix happened in the same pass). Passes 1/2/5 (debris, ASCII, lintr) were already clean
from Session 131; this session re-ran Pass 6 (`check()`/`test()`), then did a deeper
Pass 7 (security + algorithm/domain correctness) than Session 131's had covered,
live-testing against real PASTA/GBIF data rather than static review alone.

- **SSRF (Medium-High, fixed).** `.download_data_table()` (`dataone_standardize.R`) and
  `.preview_one_entity()` (`dataone_preview.R`, via `.get_content_length()`/
  `.stream_n_rows()`) used `data_url` -- read verbatim from third-party EML metadata --
  as the full request URL (host and scheme included) with no restriction. Verified live
  against a real PASTA record (`edi.1290.9`): legitimate entity-download URLs
  consistently resolve to `pasta.lternet.edu`, while other `<online><url>` entries in the
  same record pointed at five unrelated external hosts, confirming the risk is real. User
  decision: add a host allowlist. New `.pasta_trusted_hosts`/`.is_trusted_pasta_url()`
  (`dataone_standardize.R`) restrict requests to `pasta.lternet.edu`/
  `pasta.edirepository.org` over https; both call sites now skip untrusted URLs with a
  clear reason instead of requesting them. **This corrects Session 131's Pass 7a note**
  ("no high-confidence vulnerabilities found") -- that pass was a static
  `/security-review` run, not a live test against real DataONE EML data, which is what
  surfaced this gap.
- **Homonym misresolution (Medium-High, fixed).** `get_keys_from_context()`'s
  `.recover_higherrank()` (the `HIGHERRANK`-result recovery path) called
  `rgbif::name_lookup()` with no kingdom/phylum context, undermining the function's own
  stated purpose of preventing cross-kingdom homonym errors (its own documented example:
  *Alaria*, a brown alga and a trematode worm). Verified live against real GBIF data for
  *Alaria* -- confirmed `name_lookup()`'s kingdom field is genuinely noisy across
  checklist datasets, and that GBIF's backbone can even collapse distinct kingdoms to the
  same `nubKey` regardless (a GBIF data-quality limitation, not fixable here, now
  disclosed in the function's own roxygen). User decision: filter lookup hits by kingdom
  before voting. `.recover_higherrank()` gained a `context` parameter; falls back to the
  previous unfiltered behavior when no kingdom is available. `matchType =
  "LOOKUP_RECOVERED"` (a real return value the roxygen previously omitted) added to the
  documented enum and review-advice list.
- **BioTime NA-vs-absent conflation (Medium, fixed).** `read_biotime_study()` coded
  `occurrenceStatus` as `"absent"` whenever `ABUNDANCE`/`BIOMAS` was missing or failed
  `as.numeric()` coercion, not just when a value was validly zero -- risked treating
  malformed source data as a confirmed non-detection. Now `NA` when neither field parses;
  `"absent"` only for an explicit valid zero.
- **eDNA filter over-broad (Low-Medium, fixed).** `filter_gbif_quality()`'s
  `exclude_edna` pattern included generic `"bulk sample"`/`"water sample"` phrases that
  could over-exclude legitimate non-eDNA presence data; narrowed to the three
  eDNA-specific terms (`edna`, `environmental dna`, `metabarcod`).
- **Doc-only clarifications:** `make_bbox_wkt()`'s km-conversion reference didn't
  disclose it only holds along the north-south axis (`cos(latitude)` shrinkage
  east-west); `get_gbif_occurrences()`'s `rank_filter = "species"` default's exact-match
  behavior (drops `SUBSPECIES`/`VARIETY`/`FORM`) wasn't documented -- assessed as
  plausibly intentional (every existing caller already expects species-rank-only output)
  rather than changed behaviorally.
- **Zip-slip (Low, hardened defensively).** `.read_gbif_zip()` gained an entry-path check
  before `unzip()` -- `zip_path` is GBIF's own trusted API output today, but nothing
  downstream re-validates that trust.
- Test coverage: 25 new tests across `test-dataone_standardize.R` (+6),
  `test-dataone_preview.R` (**new file** -- this package's `dataone_preview.R` had zero
  test coverage before this session; `preview_dataone_occurrences()` itself is still
  untested beyond the new guard, a pre-existing gap out of scope here), `test-
  get_keys_from_context.R` (+3, synthetic mixed-kingdom fixture -- real GBIF *Alaria*
  data was tried first but is too noisy to isolate the narrowing logic cleanly),
  `test-biotime_fetch.R` (+2), `test-filter_gbif_quality.R` (+1).
- `.lintr`: added an `object_usage_linter` exclusion for `dataone_preview.R:544`
  (`.is_trusted_pasta_url()` cross-file call, same false-positive class as the existing
  `get_gbif_occurrences.R:217` exclusion, confirmed via `codetools::checkUsage()` on the
  loaded namespace); updated `get_gbif_occurrences.R`'s `commented_code_linter` line
  number (293 -> 300, drifted by this session's own doc edit above it -- see the
  pre-review-checklist memory's Pass 5 note on exclusion line-number drift).
- `devtools::document()`/`test()`/`check()` all clean: 459 expectations (up from 434),
  0 failures; 0 errors, 0 warnings, 0 notes.

**Session 140 (2026-07-06): fetch_occurrences_by_taxon() -- taxon-centric batched GBIF fetch**

Branch `main`. Implements the general-fix scope from
`ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md`, confirmed with the user
over the narrow fix (union just one multi-site observation's own sites) after re-verifying
Phase 6's live RStudio run had completed successfully post-Session-139's Section 3/5 fix.

- `fetch_occurrences_by_taxon()` added (`R/fetch_occurrences_by_taxon.R`): takes a
  `taxon_geometry_map` (one row per (site, candidate taxon) pair -- `taxon_key` + `geometry`
  WKT), unions each taxon key's own geometry via `sf::st_union()`, then (`combine_shared_geometry
  = TRUE`, default) combines taxon keys whose resulting unioned geometry is byte-identical into
  one multi-key `get_gbif_occurrences()` call. This is a pure call-grouping layer -- neither
  `get_gbif_occurrences()` nor its backends are touched. 22 new tests
  (`test-fetch_occurrences_by_taxon.R`), fully offline (`get_gbif_occurrences()` mocked via
  `local_mocked_bindings()`), covering input validation, same-taxon-overlapping-geometry union,
  different-taxa-same-geometry combination, `combine_shared_geometry = FALSE`, disjoint
  geometry (no wasted combination), duplicate-row and NA-row cleaning, and param forwarding.
- `stack_occurrences()`: added a `gbifID` dedup step (drops rows with a duplicated non-`NA`
  `gbifID`, keeps first) -- defense-in-depth per the reentry prompt's "worth doing regardless"
  recommendation. Checked first whether this was still needed given
  `TaxaMatch::standardize_match_data()` might already cover it: confirmed that function
  standardizes classifier match records (DNA/BLAST, image, acoustic -- the
  TaxaMatch -> TaxaLikely -> TaxaAssign chain) and has zero row-level dedup logic of its own; it
  is not in the GBIF occurrence -> `TaxaExpect::build_priors()` -> `model_data` path at all, so
  the gap was real, not stale. Confirmed no dedup existed anywhere in that path
  (`get_gbif_occurrences()`, `filter_gbif_quality()`, `stack_occurrences()` all checked
  directly) before adding it. 3 new tests in `test-stack_occurrences.R`.
- `inst/TaxaID_Workflow_Template_TEST.R` Section 3 restructured into the two-pass split the
  reentry prompt identified as a hard prerequisite (the old single-pass loop interleaved
  box-definition and fetching per group, making a whole-scope taxon union impossible): Pass 1
  defines every `spatial_group_id`'s search geometry with no fetching (interactive polygon for
  multi-member groups, automatic per-site bbox for single-observation groups), guarding a
  cancelled gadget immediately; Pass 2 builds one taxon_key/geometry map spanning both branches
  and fetches once via `fetch_occurrences_by_taxon()`. The escalation ladder (genus -> family ->
  order for single-observation candidates with zero hits) is now decided per starting genus
  rather than per site -- sites sharing a candidate genus already share the same escalation
  path, and this session worked through why a nonzero result anywhere in that genus's unioned
  search area means real local data exists for it, so no per-site spatial containment check is
  needed to decide whether an individual site would have escalated on its own. Zero-hit
  detection matches on the taxonomic text column (`genus`/`family`/`order`) rather than a
  `*Key` column, since not every rank has a corresponding key column in
  `.gbif_standard_columns()` (no `orderKey`) -- this makes the check rank-agnostic with no
  extra columns needed. Verified via an isolated logic test against the real
  `TaxaID_test_site_table.rds`/`TaxaID_test_BLAST.rds` checkpoints from Session 139's live run
  (mocking `get_keys_from_context()`, `escalate_taxonomic_rank()`, and `get_gbif_occurrences()`,
  since the real multi-member group in that data requires the interactive
  `define_search_polygon()` gadget): confirmed the 4-member cluster's family keys combine into
  one call (not four), a zero-hit genus is escalated and successfully refetched at its family
  rank in round 1, and the final `gbif_occurrences` assembles correctly across both rounds.
- `devtools::document()` + `devtools::test()` (434 expectations, 0 failures, 4 pre-existing
  warnings, 2 pre-existing skips) + `devtools::check()` (0 errors, 0 warnings, 0 notes) all
  clean.
- **Live-verified by the user in a real RStudio run, same session:** 3 spatial groups (2
  multi-member, 1 singleton) -- Pass 1 correctly drew search areas for the 2 multi-member
  groups and computed an automatic bbox for the singleton; Pass 2's round 0 found 4 distinct
  taxon keys (2 family, 2 genus) and issued only **2** GBIF queries, confirming the
  same-geometry-taxa combination worked on real data, not just the mocked isolated test.
  226 + 10,576 species-rank records returned; `gbif_occurrences` came back with the expected
  31-column standard schema. One cosmetic artifact noted and explained: `class` came back
  `<lgl>` (all `NA`) rather than `<chr>` -- confirmed by the user to be a known GBIF backbone
  gap for bony fishes (Actinopterygii/Actinopteri routinely missing a populated `class`
  field), not a fetch bug; the logical-vs-character type is just `get_gbif_occurrences()`'s
  pre-existing NA-fill behavior for an entirely-absent column, unrelated to this session's
  changes.
- **Not done this session:** characterizing GBIF's actual WKT-complexity ceiling (documented
  as a known, non-silently-masked limitation on `fetch_occurrences_by_taxon()` instead, per the
  reentry prompt's own item 4); cross-round query merging (an escalated taxon key can be
  re-queried in a later round at a different geometry than an earlier round's use of the same
  key, which is correct but not maximally efficient -- the final `gbifID` dedup step is the
  safety net for any resulting overlap, not a further optimization).

**Session 134b (2026-07-04): define_search_polygon() and group_observations_by_bbox() moved out**

Follow-up to Session 134 below, after the user reviewed that session's implementation and
raised package-placement questions before committing (see
`ecosystem_docs/REENTRY_PROMPT_session134b_grouping_implemented.md`). Resolution: the only
generalization `define_search_polygon()` needed to serve both a search-area purpose (this
package) and a spatial-group purpose (`TaxaMatch::group_observations_by_bbox()`) was letting
its `points` overlay be colored by an existing group column, plus letting a previously drawn
polygon be reopened for reshaping (`init_polygon` param) -- neither changes the core
interaction model, so one shared gadget covers both rather than two divergent ones.

- `define_search_polygon()` moved to **TaxaTools** (`R/define_search_polygon.R` there),
  with the `group_col` and `init_polygon` additions. Call it as
  `TaxaTools::define_search_polygon()` from this package now (see the GBIF pipeline diagram
  above). `make_bbox_wkt()`'s cross-reference updated accordingly.
- `group_observations_by_bbox()` moved to **TaxaMatch** (it operates on
  `TaxaMatch::build_site_table()`'s output -- a spatial-grouping concern, not a fetch
  concern) and was substantially reworked there (default-to-`observation_id` behavior,
  last-drawn-wins overlap rule, end-of-loop review/edit/delete step, new
  `assign_spatial_group()` manual-assignment helper). See TaxaMatch/CLAUDE.md's Session
  134b note for the full design.
- `shiny`/`miniUI`/`leaflet` dropped from this package's `DESCRIPTION` Suggests (moved to
  TaxaTools's Suggests instead) -- nothing in this package calls those namespaces directly
  anymore.
- Two workflow scripts fixed to call the new location:
  `inst/TaxaID_Workflow_Template.R` and `inst/TaxaID_Workflow_Template_TEST.R`
  (`TaxaFetch::define_search_polygon()` -> `TaxaTools::define_search_polygon()`).
- `devtools::document()` + `devtools::test()` (407 expectations, 0 failures, 4 pre-existing
  warnings/2 skips) + `devtools::check()` (0 errors, 0 warnings, 0 notes) all clean after
  the move.

**Session 134 (2026-07-03): group_observations_by_bbox() -- automatic spatial grouping**

*(Historical record -- this function and `define_search_polygon()` moved out of this
package in Session 134b, see that note above. Kept here for the original design
rationale, which still mostly applies at the new location.)*

Branch `single-observation-pipeline`. Implements the "automatic grouping" design from
`ecosystem_docs/REENTRY_PROMPT_session134_single_observation_pipeline.md`'s Thread 2 /
step 3, with one deliberate deviation from that prompt's original spec: **observations
outside every drawn group polygon (or all of them, if the user draws no polygon at all)
are placed in their own single-observation spatial group, not dropped.** The original
design (written mid-session before the user weighed in) called for dropping them with
an alert; the user redirected this before implementation started -- dropping silently
discards data the pipeline can still handle via the single-observation escalation path,
whereas keeping it as its own group costs nothing and is strictly more useful. A
`message()` always explains the reclassification (distinct wording for "some points
outside every box" vs. "no box drawn at all").

**Naming, settled before commit:** the column/param started out as `group_id`/`group_map`
with a special `"independent_<id>"` string for unboxed observations. The user flagged
this before committing: "group" is already used for unrelated concepts elsewhere in the
ecosystem (`TaxaAssign::assign_taxa_llm()`'s `context_group`/`.build_group_map()` for
LLM-batching context groups; `TaxaExpect` also uses "group" for taxonomic grouping), and
"cluster" -- the other candidate -- is *already taken* by `TaxaLikely`'s acoustic
calibration work (`cluster`/`true_cluster`/`CLUSTER_MAP` = confusable-species groups, a
completely different concept). Renamed to `spatial_group_id`/`spatial_group_map`
throughout, and dropped the separate `"independent_*"` naming convention entirely per the
user's direction: a single-observation spatial group isn't a different kind of thing, so
it gets a `spatial_group_id` with the exact same `"spatial_group_<n>"` shape as any other
group (continuing the same sequential numbering), just with one member. This cost nothing
downstream -- `update_prior_from_consensus()`'s eligibility check already worked by
counting how many observations share a `spatial_group_id` (`table()` + `>= 2L`), never by
pattern-matching the id string, so removing the special prefix required no logic changes,
only renaming.

- `define_search_polygon()`: added `points` param (data frame with `lat`/`lng`),
  overlaid as small non-interactive `addCircleMarkers()` so the user can see the actual
  observation cloud while drawing. Backward compatible (`NULL` default, no behavior
  change when omitted).
- `group_observations_by_bbox()` (new, `R/group_observations_by_bbox.R`): loops
  `define_search_polygon()`, re-centring each call on the bounding box of whatever
  observations are still ungrouped (via `.bbox_center_radius()`), until the user cancels
  the gadget (signals "done drawing groups" -- does not discard groups already
  recorded). Final assignment via `.assign_spatial_groups_from_polygons()`:
  point-in-polygon test using `sf::st_within()` (same pattern already used in
  `check_inat_range()`), first-match-wins draw order, singleton-group reclassification
  with message as described above. Both internal helpers are pure (no Shiny dependency)
  and fully unit-tested -- the interactive loop itself is not (same testing boundary as
  `define_search_polygon()` already has, gated by `interactive()`).
- Consequence for `TaxaAssign::update_prior_from_consensus()`: single-observation spatial
  groups produced here (including the newly-singleton unboxed ones) must never contribute
  to or receive that function's consensus-based prior boost -- implemented this same
  session via that function's new `spatial_group_map` param (see `TaxaAssign/CLAUDE.md`).
- 15 new tests (`test-group_observations_by_bbox.R`), fully offline. `devtools::test()`:
  422 expectations, 0 failures (4 warnings/2 skips pre-existing). `devtools::check()`:
  0 errors, 0 warnings, 0 notes.
- **Not done this session** (see `ecosystem_docs/REENTRY_PROMPT_session134...` follow-up
  for the next session): wiring `spatial_group_id` into the actual occurrence/reference
  fetch calls (pooled fetch for multi-member groups vs. per-observation taxonomic
  escalation for single-observation groups) -- the escalation ladder itself (genus ->
  family -> order) was only validated empirically in ad hoc session scripts last session,
  not yet built as a reusable function anywhere in the ecosystem.

Sessions 26–80 archived in ecosystem_docs/session_notes/TaxaFetch_sessions.md.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.
- `combine_occurrence_sources()` dead code deleted (superseded by `rename_cols()` +
  `stack_occurrences()` since Session 19). File + Rd deleted; `@seealso` refs updated.
- 5 stale inst/ files deleted: `TaxaFetch_workflow copy.R`, `migrate_prompt_api.R`,
  `habitat_scheme_workflow.R`.

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaFetch-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools),
  WERC review integration. Deferred: `call_api_pdf()` generic (multimodal/PDF
  call cannot be trivially unified with `call_api`; tracked as TODO in TaxaID/CLAUDE.md).

**Session 86 (2026-05-23)**
- `screen_pdf_structure()`: `llm_fn` fallback updated from `call_anthropic_api` to
  `TaxaTools::call_api`. Clears TODO from Sessions 82/85.
- `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at TaxaID/ root).

**Session 87 (2026-05-26)**
- `call_api_pdf()` generalized to support any vision-capable LLM provider.
  Replaces hardcoded Anthropic HTTP block with `TaxaTools::call_api(images = page_images)`.
  New params: `provider`, `tier`, `base_url`; `model` and `api_key` now default NULL
  (resolved by `call_api()`). Clears TODO from Sessions 83-85.
  Providers: Anthropic (claude-sonnet-4-6), Gemini (2.5 Flash/Pro), OpenAI (GPT-4o),
  Ollama vision models (llava-llama3). PDF rendering (.render_pdf_pages) unchanged.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 105 (2026-06-10)**
- `fetch_gbif_occurrences()`: HTTP 503 "Service Unavailable" errors now retried with
  exponential backoff (5/10/20/40 sec) in addition to existing 429 retry (30/60/120/240 sec).
  Previously 503s were silently skipped, causing all keys to fail during an outage.
- **Abort-on-exhaustion policy**: any key that exhausts all retries now causes an
  immediate `stop()` rather than silently skipping. Skipping would produce
  session-inconsistent results (different keys processed on different runs).
- **Checkpoint / resume**: `cache_dir` parameter added (default:
  `tools::R_user_dir("TaxaFetch", "cache")`). Progress saved after each completed
  chunk. On abort, re-running with the same arguments resumes automatically.
  Checkpoint filename encodes the call signature (key count, key sum, geometry
  length, year range, limit) so changed parameters start fresh without collisions.
  `.gbif_checkpoint_path()` internal helper builds the deterministic path.
- `.fetch_chunk()` return value changed from bare data.frame/NULL to
  `list(records, aborted)` to propagate abort signal to the outer loop cleanly.
- Diagnosis: GBIF API returned `"HTTP 503 Backend fetch failed"` (request XID in
  response body) for all keys during a confirmed infrastructure outage; confirmed
  by raw `curl` to the GBIF occurrence search endpoint.
- `devtools::test()` (test-fetch_gbif_occurrences.R): 18 pass, 0 fail, 2 skip.
  Tests updated to use `out$records`, and resilience test updated to expect
  `stop()` (not warning + partial results) on key failure.

**Session 114 (2026-06-22)**
- `filter_gbif_quality()`: `exclude_absent = TRUE` parameter added (new filter step 2, before basis-of-record).
  Removes records where `occurrenceStatus = "ABSENT"` — explicit non-detections from systematic surveys.
  These are present in GBIF downloads and must not be used as presence data for priors or occurrence modelling.
  Root cause: GBIF `occurrenceStatus = "ABSENT"` rows were inflating occurrence counts (e.g. Haliotis corrugata).
  Filter logic: `is.na(occurrenceStatus) | toupper(trimws(occurrenceStatus)) != "ABSENT"` (retains NA rows).
  `"occurrenceStatus"` added to `utils::globalVariables()`. `@param exclude_absent` roxygen doc added.
  Filter order updated: coordinates → absent occurrences → basis → issues → uncertainty → precision → eDNA → species.

**Session 111 (2026-06-16)**
- `define_search_polygon()` added: interactive Shiny gadget for defining custom WKT search polygons.
  Replaces `make_bbox_wkt()` when a non-rectangular region is needed (e.g. coastal transects where
  a square bbox wastes download bandwidth over open ocean / inland areas).
- Signature: `define_search_polygon(lat, lon, radius_deg, tile = "Esri.OceanBasemap")`.
- Initial square: 4 corner markers (SW→SE→NE→NW, counter-clockwise, IDs 1–4).
- Vertex dragging via `leaflet::addMarkers(options = markerOptions(draggable = TRUE))` — NOTE:
  `addCircleMarkers(draggable = TRUE)` does NOT work (Leaflet.js `L.CircleMarker` limitation).
- Add Point: finds longest segment by squared Euclidean distance, inserts new draggable vertex at midpoint.
- Remove Last Point: removes highest `id > 4` row; protects original 4 corners.
- Returns WKT `POLYGON ((lng lat, ...))` string; ring closed (first == last vertex).
- Requires `shiny`, `miniUI`, `leaflet` (checked at runtime with informative error if missing).
- Tested against Mugu workflow coordinates via `devtools::load_all()`.

**Session 107 (2026-06-11)**
- `download_gbif_occurrences()` added: async GBIF bulk download for large key sets (100s–1000s).
  Root cause of existing 429 rate limits: `fetch_gbif_occurrences()` hit key 511/1598 before abort.
- Critical bug fixed during development: GBIF download API `taxonKey` predicate is exact-match only
  (not hierarchical like `occ_data()`). Fix: `pred_or(pred_in("familyKey",...), pred_in("genusKey",...),
  pred_in("speciesKey",...), pred_in("taxonKey",...))`. Without this, family-level queries returned
  only family-rank-identified records (no species data).
- SIMPLE_CSV format notes: `familyKey`, `genusKey` etc. are DWCA-only and absent from SIMPLE_CSV —
  hierarchy validation removed. The `issue` (singular) → `issues` (plural) rename for
  `filter_gbif_quality()` compatibility is implemented in this function (see the
  `simple_csv_renames` block after import) and works correctly. **Correction (Session 131):**
  a Session 129 note here previously claimed this rename "was never actually implemented" and
  that the column comes out as `issue`, not `issues` — that claim was wrong. Re-verified directly
  against a real cached SIMPLE_CSV file (`.read_gbif_zip()` + the rename block, run against a real
  download zip): before the rename block runs, the column is `issue`; after, it is `issues`. The
  code has been unchanged since this function's first commit. The false claim led
  `get_gbif_occurrences()` to carry a redundant (harmless, but dead) second rename — removed in
  Session 131.
- `filter_gbif_quality()`: `require_species` parameter added (filter 7). Needed because GBIF returns
  all ranks within a queried family/genus, including genus-only records with no species value.
- `data.table` added to DESCRIPTION Suggests; `quote=""` in fread suppresses spurious quoting
  warnings on GBIF TSV data.
- User-facing messaging improved: cache directory printed at start; "still working" message after
  rgbif "succeeded" output (which misleadingly appears before import completes).

**Session 129 (2026-07-03): get_gbif_occurrences() unified entry point**
- `R/get_gbif_occurrences.R` added — formalizes the manual dispatch pattern the Layer-1
  tutorial (below) already documented informally: picks `fetch_gbif_occurrences()` vs
  `download_gbif_occurrences()` by `key_threshold` (default 50), standardizes both paths
  to one column contract, and defaults to species-rank-only output (`rank_filter =
  "species"`, post-fetch only — neither GBIF API has a rank predicate to filter
  server-side). Neither `fetch_gbif_occurrences()` nor `download_gbif_occurrences()` is
  modified. **Correction (Session 131):** this entry originally said the wrapper "fixes
  the issue/issues column-name mismatch on the download path" — `download_gbif_occurrences()`
  already renames it correctly on its own (see that function's Session 131 correction
  above); there was no mismatch to fix. `get_gbif_occurrences()`'s redundant second
  rename was removed in Session 131; the wrapper's `select_cols` translation (`issues`
  → `issue`, needed because `select_cols` matches SIMPLE_CSV's native column names at
  import time, before the rename happens) is unaffected and still correct.
- **Known pre-existing issue found while running a final test pass, NOT related to the
  above:** `tests/testthat/test-build_iucn_scheme.R`, `test-llm_api_utils.R`, and
  `test-parse_hierarchical_habitat_response.R` all test functions that moved to
  TaxaHabitat/TaxaTools in the Session 28 package split and no longer exist in this
  package — they've been failing since before any tracked git history. **Deleted this
  session (confirmed by user) — see follow-up note below.**

**Session 130 (2026-07-03): stale test files deleted; check()-vs-test_dir() root-caused**
- Deleted the 3 stale test files noted above. `devtools::test()`: 0 failures, 0 errors.
  `devtools::check()`: 0 errors, 0 warnings, 0 notes.
- While re-verifying, a bare `testthat::test_dir("tests/testthat")` run (not
  `devtools::test()`) flagged a 4th apparently-stale file, `test-biotime_fetch.R`
  (`could not find function "read_biotime_study"`) — a false alarm. `read_biotime_
  study()` is real and correctly exported (`R/biotime_fetch.R`); bare `test_dir()`
  doesn't `load_all()`/attach the package first, so it can spuriously report missing
  functions. This is almost certainly the explanation for the earlier `check()`-vs-
  `test_dir()` discrepancy noted above — `devtools::check()`'s bundled test run does the
  equivalent of `load_all()` first, which is why its summary was trustworthy the whole
  time. Root-caused; written into the pre-review-checklist memory as the general rule
  (always use `devtools::test()`, never bare `test_dir()`).

**Session 123 (2026-07-01): Layer-1 workflow script**
- `inst/workflows/fetch_occurrences_workflow.R` added — teaching-oriented, fully namespaced,
  runnable top to bottom on a built-in tutorial example (genus *Gadus*, North Atlantic).
  Demonstrates `get_keys_from_context()` → GBIF two-path dispatch (`fetch_gbif_occurrences()`
  vs. `download_gbif_occurrences()`, threshold at ~50 keys) → `filter_gbif_quality()` →
  `stack_occurrences()`. Narrow/broad-marker VARIANT A/B preserved from the old monolithic
  templates; broad-marker sampling_group assignment left as a TODO pointer (see
  `ecosystem_docs/LAYER1_WORKFLOWS.md`), not inline code.
- Live-tested against real GBIF (part of a 5-package full-chain smoke test through TaxaFlag).
  Full design rationale, cross-package continuity conventions, and bugs found/fixed during
  testing are in `ecosystem_docs/LAYER1_WORKFLOWS.md` — see that file, not this one, for the
  complete record.

**Session 131 (2026-07-03): pre-code-review cleanup, all 9 checklist passes**

Full pass-by-pass cleanup ahead of TaxaFetch's scheduled code review (continuing from
Session 130's stale-test-file deletion). `devtools::test()`: 407 expectations, 0 failures,
0 errors (2 expected skips, 4 expected warnings from tests deliberately checking warning
messages). `devtools::check()`: 0 errors, 0 warnings, 1 NOTE (`unable to verify current
time` -- an environment/clock artifact, not code-related).

- **Pass 1 (debris):** deleted `inst/Habitat_assign_workflow.R` (called 5 functions moved
  to TaxaHabitat in the Session 28 split, same stale-debris pattern as the 3 test files
  Session 130 deleted) and `inst/all_occurrences.rds` (806KB untracked leftover, unreferenced
  by any script). Removed a dead `.Rbuildignore` entry for a file already deleted Session 82.
- **Pass 2 (ASCII):** swept all of `R/` for non-ASCII characters (em-dashes, en-dashes,
  arrows, box-drawing separator lines) across 9 files -- none had been checked since before
  this session; all replaced with ASCII equivalents, no semantic changes.
- **Pass 3 (naming) -- major correction:** re-verified the Session 129 claim that
  `download_gbif_occurrences()` doesn't rename SIMPLE_CSV's `issue` column to `issues`.
  **That claim was wrong.** Tested the actual rename block directly against a real cached
  GBIF SIMPLE_CSV zip: the rename works correctly, and has been in place unchanged since the
  function's first commit (2026-06-11) -- there was never a version without it. Corrected
  the false claim everywhere it had propagated: this file's Session 107/129 notes, and
  `get_gbif_occurrences()`'s roxygen `@details` (which described fixing a "known asymmetry"
  that didn't exist). Removed `get_gbif_occurrences()`'s now-provably-dead redundant second
  rename block (its guard condition was never true) and the now-stale
  `utils::globalVariables("issue")` declaration alongside it. Also renamed 3 ALLCAPS
  module-level constants in `dataone_occurrence_search.R` (`.PASTA_SOLR`, `.PASTA_META`,
  `.DEFAULT_BIO_KEYWORDS` → `.pasta_solr_url`, `.pasta_meta_url`, `.default_bio_keywords`)
  and one over-length internal helper name in `pdf_characterize.R`
  (`.non_occurrence_legend_keywords` → `.non_occurrence_keywords`, was 31 chars) for
  lintr's `object_length_linter` and ecosystem naming consistency.
- **Pass 4 (doc completeness):** `check_inat_range()` was the only exported function
  missing `@examples` -- added a `\dontrun{}` example (requires `INAT_API_TOKEN`).
  Also found and removed a stale "withr dependency" note in this file's "Key Notes for
  Claude" and "Key Dependencies" sections -- no test in the package uses `withr`, and it
  was never actually added to `DESCRIPTION` Suggests despite the note's claim.
- **Pass 5 (lintr):** created `.lintr` (line length 120, UTF-8). Fixed for real:
  10 `brace_linter` (inconsistent if/else brace usage), 10 `semicolon_linter` (compound
  statements split to separate lines in `dataone_occurrence_search.R`), 3
  `object_name_linter` (the constant renames above), 1 `object_length_linter` (the helper
  rename above), 8 `line_length_linter` (long `stop()`/`warning()`/`message()` strings
  split via `paste0()`), 2 `trailing_blank_lines_linter`, 1 `trailing_whitespace_linter`,
  2 `return_linter` (`return(NULL)` → bare `NULL` in `tryCatch` error handlers). Added
  `.lintr` `exclusions` for ~60 `commented_code_linter` false positives (legitimate
  top-of-file "workflow mirror" example comments and short English phrases that happen to
  parse as valid R, e.g. `# ID / citation` as a division expression) and one
  `object_usage_linter` false positive in `get_gbif_occurrences.R` (confirmed via
  `codetools::checkUsage()` against the loaded namespace that the flagged
  `exclude_absent = exclude_absent` forwarding is real and correct; `lint_package()`'s
  per-file static analysis just doesn't resolve the cross-file call).
- **Pass 6:** re-ran `devtools::document()`/`test()`/`check()` after all edits above --
  still clean.
- **Pass 7a (security):** `/security-review` found no high-confidence vulnerabilities.
  All external API calls (GBIF, DataONE, OpenAlex, iNaturalist, LLM providers) use
  environment-variable credentials, trusted per this project's security model.
- **Pass 7b (algorithm/domain correctness):** a 6-angle `/code-review` pass (line-by-line,
  removed-behavior audit, cross-file tracer, reuse, simplification/efficiency,
  altitude/conventions) over the full session diff found: the stale `globalVariables`
  declaration (fixed, see Pass 3 above); the new `test-download_gbif_occurrences.R`
  reimplementing an env-var save/restore dance for a credential-missing test when passing
  empty-string args directly (matching `test-check_inat_range.R`'s existing convention) was
  simpler -- rewritten; the same test's synthetic-zip fixture builder used an unnecessary
  `setwd()`/`on.exit()` dance and depended on an external `zip` binary via `utils::zip()` --
  rewritten using `zip::zip()`'s `root` argument (added `zip` to `DESCRIPTION` Suggests),
  which is both simpler and removes the external-binary portability risk; a hand-rolled
  `runif()`-based temp-directory-uniqueness scheme was replaced with `tempfile()`. Also
  added `tests/testthat/test-get_gbif_occurrences.R` (9 tests) -- `get_gbif_occurrences()`
  had zero test coverage of its own before this session, including of the exact
  column-name-translation logic (`select_cols_dl`) that the Pass 3 correction above was
  about; this closes that gap so the false claim's root cause (an unverified assumption,
  never pinned down by a test) can't recur silently.
- **Cross-package fallout from the `inst/Habitat_assign_workflow.R` deletion:** two review
  agents independently found the deletion left 5 dangling path references in *other*
  packages (found via full-monorepo grep, confirmed with the user before fixing, since it
  touches files outside TaxaFetch): `TaxaID/README.md`'s workflow-script table, both the
  diagram and prose in `ecosystem_docs/ECOSYSTEM_WORKFLOW.md`, a comment in
  `TaxaExpect/inst/TaxaExpect_workflow.R` (two spots), and a comment in
  `TaxaWizard/inst/graph/snippets/occ_to_std.R`. All 5 repointed to TaxaHabitat's current
  script, `TaxaHabitat/inst/workflows/assign_habitat_workflow.R`.
