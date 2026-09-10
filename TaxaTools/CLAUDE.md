# CLAUDE.md -- TaxaTools
# Last updated: 2026-09-04 (Sonnet 5, branch cache-management -- NEW cache_utils.R:
# list_cache_files()/report_and_clear_cache(), a shared engine for a downstream
# package's own <pkg>_clear_cache() helper.
#
# Grew out of fixing a real TaxaFetch bug (a 23GB GBIF-zip cache with an orphan-
# accumulation bug -- see TaxaFetch/CLAUDE.md) and finding TaxaLikely had the same
# unbounded-cache shape (fetch_ncbi_reference_sequences()/audit_barcode_coverage(),
# one small file per query, no eviction). Both packages already import TaxaTools
# (same precedent as %||%), so rather than duplicate the ~40-line validate/report/
# delete logic in each package's own <pkg>_clear_cache() wrapper, it now lives once
# here: list_cache_files(cache_dir, patterns) (directory scan by regex, returns
# path/size_mb/mtime) + report_and_clear_cache(inv, label, cache_dir,
# older_than_days=, dry_run=) (age filter + report + delete). Each downstream
# package keeps its own separately-NAMED, separately-exported wrapper
# (TaxaFetch::taxafetch_clear_cache(), TaxaLikely::taxalikely_clear_cache()) --
# never one shared function name, since two loaded packages both exporting a bare
# clear_cache() would mask each other. TaxaFetch's own orphan-detection logic
# (reading a zip's meta.rds to tell "current" from "superseded" -- no TaxaLikely
# analog) stays local to that package, pre-filtering its own inventory before
# handing off to the shared engine.
#
# Deliberately fits ONLY the "directory of many small, deterministically-keyed
# files" cache shape -- checked directly before building this and confirmed
# TaxaMatch's reference-evaluation caches are a different, CUMULATIVE shape (one
# consolidated file, row-level TTL, "congruent" verdicts cached forever by
# design) that a directory-scan-and-delete engine would be actively wrong for;
# left untouched.
#
# devtools::test() 893/0, devtools::check() 0/0/0, reinstalled.
# Previous update, 2026-09-03 (Opus 5, branch kernel-priors -- NEW resolve_barcode_marker().
#
# A registered primer-variant term ("COI-Folmer", "16S-Palumbi", "rbcLa", "cytb-Kocher",
# "matK-Kim", "trnL-Taberlet") is the right term for resolving primers and amplicon lengths, but
# NO sequence database indexes it -- no GenBank record is tagged "Folmer". Any NCBI query built
# from such a term matched NOTHING, and because an empty search result is legitimate, the failure
# was SILENT: downstream it read as "this taxon has no barcode", not "this query was malformed".
#
# Live-confirmed before and after: Leptocottus COI 0 hits -> 23, Paralabrax 0 -> 46, Girella
# 0 -> 15. Found when a workflow's COI term was changed "COI" -> "COI-Folmer" to resolve a
# genuine resolve_barcode_primers() ambiguity; the defect predated that change and covered every
# registered variant except the MiFish pair.
#
# resolve_barcode_marker() maps a variant to the marker it amplifies. Identity for anything
# unrecognised, so a custom term still searches as itself. MiFish is deliberately NOT remapped --
# real records ARE annotated with that primer name, and callers already OR it with 12S. It lives
# here, not in TaxaLikely, because the same failure reached THREE packages (TaxaLikely's
# .build_search_term and audit_barcode_coverage, TaxaAssign's suggest_unreferenced_species) and
# TaxaTools already owns the primer/length registries the terms come from.
#
# The two SILENT consumers were the dangerous ones: audit_barcode_coverage() and
# suggest_unreferenced_species() would have reported every species as having no barcode,
# inflating `unreferenced` and feeding apply_coverage_constraints() and the unobserved-taxa
# machinery a fiction that looks like a finding.
#
# 6 new tests. devtools::test() 865/0, devtools::check() 0/0/0, reinstalled.
# CLAUDE.md — TaxaTools
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Previous update: 2026-08-21 (Sonnet 5 -- clean_taxon_names() gains a new `collapsed_to_genus`
# R attribute on its returned vector, closing the ROOT CAUSE of a real "Ictalurus" bug found
# live-debugging real GreatLakes2023 production data (`match_obj_restored %>% filter(
# taxon_name_rank == "species", taxon_name == "Ictalurus")` returned 33 real rows). User's
# explicit framing before any fix was written: "We have not shipped the package... let's
# think carefully about a robust way to fix this problem that does not require repeated
# post-hoc fixes." Traced the FULL chain, not just the symptom: TaxaLikely::
# restore_suppressed_candidates()'s `.build_restored_row()` copies a reference row's raw
# species value (e.g. "Ictalurus cf. pricei USON-01120-1", a specimen-voucher-tagged NCBI
# open-nomenclature label) into a restored candidate row, then calls
# `TaxaTools::create_taxon_names()`, which sets `taxon_name_rank = "species"` purely because
# the species column is POPULATED -- it never inspects the value's own shape. This is
# correct, documented `create_taxon_names()` behavior (column-occupancy-only derivation,
# confirmed too central/high-blast-radius to change unilaterally -- "one of the most-called
# internal functions" per this file's own Design Notes) and NOT where the fix belongs.
#
# `clean_taxon_names()` itself was ALSO already behaving correctly, collapsing the
# open-nomenclature label to genus-only ("Ictalurus") exactly as documented -- but it
# discarded the one piece of information a caller needs to correct `taxon_name_rank`
# alongside the name: whether a collapse actually happened. The function already computes
# this internally (`keep_epithet`) and simply never surfaced it. Fixed additively: a new
# `collapsed_to_genus` logical attribute (same length as the input) is now attached to the
# returned vector -- `TRUE` only when a real second token was present and dropped (not for
# input that was already genus-only, and not for rejected/`NA` output). Zero behavioral
# change to the returned character vector itself; every pre-existing caller that only reads
# the plain vector is unaffected (confirmed: `expect_equal()` on the bare vector needed
# `ignore_attr = "collapsed_to_genus"` added to ~30 pre-existing assertions in this file's
# own test suite -- a mechanical, non-substantive update, not a behavior change).
#
# The user's own follow-up question -- "Does the fix interact with
# convert_taxonomy_backbone(), fill_higher_ranks()?" -- was answered by tracing the real
# data flow directly, not by inspection alone: `TaxaMatch::convert_taxonomy_backbone()` DOES
# run on this exact restored-candidate data (same real workflow, right after
# `restore_suppressed_candidates()`), and it already has its OWN, separate rank-correction
# mechanism from the 2026-07-25 "Inu Inu" fix -- but that mechanism only fires for a row the
# target backbone actually FOUND (just at a coarser rank than claimed), driven by
# `verify_taxon_names()`'s `matched_rank` field. "Ictalurus cf. pricei USON-01120-1" is a
# full open-nomenclature string with a specimen voucher tag, essentially certain to fail an
# exact-name backbone lookup entirely (`found_mask = FALSE`) -- a genuinely different code
# path the existing mechanism has no coverage for at all. `fill_higher_ranks()` was checked
# too and confirmed genuinely unrelated: it never calls `clean_taxon_names()`, and its own
# `genus` correction is driven by the same `matched_rank == "genus"` backbone-synonym signal,
# not a local syntactic collapse. See `TaxaMatch/CLAUDE.md`'s matching 2026-08-21 note for
# the actual consuming-side fix built on this new attribute (a wholly new not-found-row
# demotion block in `convert_taxonomy_backbone()`, genuinely separate from its existing
# found-row correction, not a modification of it).
#
# `devtools::test()` 847/847 (0 failures, 10 pre-existing/expected warnings), `devtools::
# check()` 0 errors/0 warnings/1 pre-existing note (timestamp verification, environmental).
# Reinstalled and verified at `~/Library/R/4.0/library`; live end-to-end smoke test against
# the installed package (not just `load_all()`) confirms the real motivating case now
# resolves correctly through both packages together -- see TaxaMatch/CLAUDE.md's note for
# the exact command and output.
# Previous update, 2026-07-25, later same day (Sonnet 5 -- fill_higher_ranks() now corrects
# `genus` (not just `family`) to the backbone's resolved name when an API lookup shows the
# queried genus is a taxonomic synonym at genus rank, closing a real consistency gap the
# user asked to double-check after the same-day verify_taxon_names()/convert_taxonomy_
# backbone() fix (see this file's own note directly below and TaxaMatch/CLAUDE.md's
# matching note). Before this fix, fill_higher_ranks() always returned genus as the
# locally-extracted first word of the input name, UNCHANGED even when the API response
# showed it was a synonym -- live-confirmed: querying the real "Inu" case under GBIF
# returned genus="Inu"/family="Gobiidae" even though verify_taxon_names("Inu",
# backbone_id=11) directly returns matched_name="Luciogobius". This wasn't just cosmetic:
# traced a real consuming call site, TaxaAssign::join_priors()'s .expand_coarse_rank_rows()
# (R/join_priors.R ~line 137-139), which does an EXACT STRING match between a likelihood-
# side coarse taxon_name (now correctly "Luciogobius" post the convert_taxonomy_backbone()
# fix) and expansion_taxonomy's genus column (built via fill_higher_ranks() on
# taxaexpect_priors$taxon_name) -- before today's TaxaMatch fix, both sides agreed on the
# synonym form by coincidence; after it, only one side was corrected, so the join would
# have started silently failing for any taxon in this situation, losing real occurrence-
# based coarse-rank expansion and falling back to the dark-diversity floor instead.
# Fixed by having .lookup_family_from_backbone() (R/fill_higher_ranks.R) return a new
# resolved_genus field alongside the existing query-genus join key (genus stays the LOOKUP
# key so the left_join() back into `work` still works; resolved_genus is coalesced into
# work$genus only where a match was actually found, keeping genus correction and family
# resolution in lockstep) -- substitution only applied when matched_rank == "genus"
# specifically (defensive: never trust a resolved name at a coarser rank as a genus
# substitution). Gracefully skipped (genus passes through unchanged) when verify_fn's
# response has no matched_rank column, same backward-compat contract as the
# convert_taxonomy_backbone() fix. 3 new tests (genus corrected for a real synonym case;
# genus unchanged with a pre-2026-07-25-shaped mock response; genus unchanged when
# matched_rank is present but not "genus"). Live-reverified against the real Inu case
# post-reinstall: fill_higher_ranks() now correctly returns genus="Luciogobius" under
# GBIF, matching convert_taxonomy_backbone()'s own output for the same taxon.
# devtools::test() 0 failures (829, up from 824), devtools::check() 0/0/0. Reinstalled to
# ~/Library/R/4.0/library. escalate_taxonomic_rank() was also checked and found to have NO
# analogous issue -- it never reads matched_name at all, and walks classification_path by
# NAMED rank rather than trusting current_rank to index a specific position, so a
# rank/synonym mismatch degrades to an honest NA rather than a wrong value; no changes
# needed there.
# Previous update, 2026-07-25 (Sonnet 5 -- verify_taxon_names() gains matched_rank/is_synonym
# columns and internally corrects two real name-quality bugs, prompted by a real "Inu Inu"
# fabricated-pseudo-binomial artifact the user found in real Mugu output (see TaxaFlag/
# TaxaAssign/TaxaMatch's own same-day session notes for the full debugging chain that led
# here). Root cause traced precisely: an NCBI reference sequence labelled "Inu sp. 1 sensu
# Shibukawa et al., 2020." (an informally-named goby) resolves against GBIF to genus
# "Luciogobius" -- GBIF's own backbone considers "Inu" Snyder 1909 a taxonomic SYNONYM of
# "Luciogobius" Gill 1859 -- with no species-level entry to fill. Two real, separate bugs
# in this function fed that: (1) matched_name was read from GNVerifier's matchedName field
# (the synonym form, "Inu") rather than currentName (the accepted form, "Luciogobius") even
# when the API's own isSynonym flag said to prefer it; (2) the local strip_authority()
# regex (genus + AT MOST one lowercase word) silently truncated any subspecies-rank match
# to a binomial -- confirmed live: "Delphinus delphis ponticus Barabash, 1935" ->
# "Delphinus delphis", dropping "ponticus" entirely. Fixed by switching from
# strip_authority(matchedName) to GNVerifier's own matchedCanonicalSimple/
# currentCanonicalSimple fields directly (already authority-free, already rank-complete,
# no local regex needed) and preferring the current field when isSynonym is TRUE. New
# matched_rank column (derived via new .last_classification_rank() helper, shared by both
# the GNVerifier-API path and the NCBI-direct-bypass path) reports the rank the match
# ACTUALLY resolved at -- fixes the second half of the Inu bug (TaxaMatch::
# convert_taxonomy_backbone() had no way to know a match came back genus-only rather than
# species-level, so it kept reporting a stale "species" rank label on a bare genus name;
# see that package's own same-day note for the consuming-side fix). Verified backbone-
# general, not GBIF-specific, before shipping: live-queried the SAME real query across 5
# backbones (Catalogue of Life, ITIS, NCBI, WoRMS, GBIF) -- matched_rank/matchedCardinality
# are normalised identically by GNVerifier across all of them; isSynonym/currentName are
# populated identically in MECHANISM but differ in real, substantive DATA (NCBI's own
# taxonomy does not consider "Inu" a synonym at all, a genuine cross-authority disagreement,
# not a bug) -- confirming the fix is built entirely from already-backbone-scoped GNVerifier
# fields with no GBIF-specific code anywhere. backbone_id=4 (NCBI) never reaches this API
# path at all (uses .verify_via_ncbi() instead, which has no synonym data to draw on) --
# its own matched_rank is populated identically via the shared helper regardless. 6 new
# live/online tests added (this file's existing established convention -- no offline mock
# infrastructure exists here), including a direct reproduction of the real Inu case and the
# real subspecies-truncation case. devtools::test() 824/824 (up from ~818), devtools::check()
# 0/0/0. Reinstalled to ~/Library/R/4.0/library. See TaxaMatch/CLAUDE.md's same-day note for
# the convert_taxonomy_backbone() consuming-side fix, and TaxaID/CLAUDE.md's Recent Breaking
# Changes table for the full cross-package record.
# Previous update, 2026-07-06 (Session 142 — barcode_primer_defaults gains coi-leray
# (mlCOIintF/dgHCO2198, Leray et al. 2013 / Meyer 2003), the actual eDNA-relevant COI
# mini-barcode -- pairs Leray's own inosine-free forward primer with Meyer's inosine-free
# degenerate reverse primer (not Geller et al. 2013's jgHCO2198, which uses inosine and has
# no representation in Biostrings::DNAString's IUPAC alphabet), avoiding the workaround
# flagged as unresolved in Session 141. bare "COI" is now deliberately ambiguous between
# coi-folmer and coi-leray -- callers must specify which fragment their data actually is.
# See Session 142 note below for the discriminatory-power literature review that preceded
# this addition.
# Session 141 — barcode_primer_defaults expanded from MiFish-only to
# 6 more real, independently-verified primer sets covering every mitochondrial and chloroplast
# marker in barcode_length_defaults (16S, COI, cytb, rbcL, matK, trnL) -- nuclear markers (18S,
# ITS/ITS2) deliberately skipped per the user's own direction, since neither has one canonical
# primer pair to verify. Each entry empirically tested against a real GenBank mitogenome/
# chloroplast genome (not just cross-checked against literature), which caught two real errors
# a literature-only check would have missed: a wrong cytb amplicon length repeated by two
# secondary sources, and a genuine forward/reverse mislabeling in an otherwise-authoritative
# primer table for matK. See Session 141 note below for the full record.
# Session 140 — barcode_primer_defaults + resolve_barcode_primers()
# added: a new primer-sequence registry (MiFish-U/E only, verified against Miya et al. 2015
# across three independent sources), consumed by TaxaLikely::trim_to_amplicon() for in-silico
# PCR amplicon extraction. Deliberately does NOT mirror barcode_length_defaults' generic
# substring matching for a bare "mifish" -- U and E have genuinely different primer
# sequences, so resolve_barcode_primers() errors on ambiguity rather than guessing. See
# Session 140 note below and TaxaLikely/CLAUDE.md's own Session 140 note for the full record.
# Session 137 — escalate_taxonomic_rank() added: the escalation-
# ladder function (genus -> family -> order broadening for singleton observations with no
# reference/occurrence data at their own rank), Phase 1 of the observation-pipeline-wiring
# reentry plan. Reuses verify_taxon_names()/parse_classification_path(); same primary/
# fallback-backbone pattern as fill_higher_ranks(). Live-verified against real NCBI data for
# the PtConception 12S cases and the bobcat-photo case. See Session 137 note below.
# Session 134b — define_search_polygon() moved here from TaxaFetch:
# the shared interactive polygon gadget for both TaxaFetch's search-area use and TaxaMatch's
# spatial-group use (group_observations_by_bbox()). Added group_col (color the points overlay
# by an existing group column), init_polygon (reopen a previously drawn polygon for
# reshaping), and viewer (default shiny::paneViewer(minHeight = 500) -- RStudio's
# dialogViewer() was found, via real live-testing, to silently break this gadget's Done
# button; paneViewer() confirmed working and matches this ecosystem's other mapping
# gadgets) params. shiny/miniUI/leaflet added to Suggests. See Session 134b note below.
# Session 122 — is_valid_species_name() → is_plausible_binomial() rename; call_api()
# data-sensitivity @details added; startup message data-transmission NOTE added; README.md
# Code Style + lintr-sweep reminder added; man/figures/README-pressure-1.png debris deleted)

---

## Package Purpose
Shared helper functions for working with taxonomic name lists AND LLM API providers.
Dependency of all other TaxaID packages. Can also be used standalone for cleaning and
standardizing taxon name lists, resolving synonyms, and querying taxonomic hierarchies.

---

## Function Inventory

### Taxonomy functions

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `verify_taxon_names()` | Verify names against a taxonomic backbone via Global Names Verifier API; batched; returns `user_supplied_name`, `matched_name`, `matched_rank`, `is_synonym`, `classification_path`, `classification_ranks`, `score`, `verified`. **2026-07-25**: `matched_name` now sourced from GNVerifier's own `matchedCanonicalSimple`/`currentCanonicalSimple` fields (authority-free, rank-complete) rather than a local regex — preserves a full trinomial at subspecies rank (previously silently truncated to a binomial) and prefers the backbone's currently-accepted name over a synonym when `is_synonym = TRUE`. New `matched_rank` reports the rank the match actually resolved at (may be coarser than the query implied — e.g. a species-level query resolving only to genus). Backbone-general, not GBIF-specific: `matched_rank` is normalised identically by GNVerifier across every backbone; `is_synonym`/`currentName` reflect each backbone's own real taxonomic opinion (verified: NCBI and GBIF can genuinely disagree on whether a name is a synonym). `backbone_id = 4` (NCBI) bypasses this API entirely (`.verify_via_ncbi()`) and never gets synonym data, but still gets `matched_rank`. | Complete | R/verify_taxon_names.R |
| `create_taxon_names()` | Add `taxon_name` and `taxon_name_rank` columns from separate rank columns; case-insensitive column matching; most-specific non-NA rank wins | Complete | R/create_taxon_names.R |
| `clean_taxon_names()` | Normalise, deduplicate, and filter a character vector of taxon names; removes NA, non-capital-initial, abbreviations, bracket artefacts; converts underscore-encoded binomials (`Genus_epithet`) to space-separated (Jonah Ventures / SILVA pipelines). **2026-08-21**: returned vector gains a `collapsed_to_genus` R attribute (logical, same length) -- `TRUE` when a row HAD a real epithet-shaped second token that was dropped (e.g. an open-nomenclature label collapsing to genus-only), letting a caller building `taxon_name`/`taxon_name_rank` pairs correct the rank alongside the name. See `TaxaMatch::convert_taxonomy_backbone()`'s consuming-side fix. | Complete | R/clean_taxon_names.R |
| `change_backbone()` | Post-process `verify_taxon_names()` output; rename source/translated name columns; parse pipe-delimited classification into wide rank columns | Complete | R/change_backbone.R |
| `rename_cols()` | Rename data frame columns using an explicit `col_map` or built-in case-insensitive regex patterns for common DarwinCore alternatives; `strict` arg controls missing-key behaviour | Complete | R/rename_cols.R |
| `find_taxonomy_conflicts()` | Detect higher-rank inconsistencies in taxonomy data frames; returns `taxon_name`, `taxon_rank`, `parent_rank`, `parent_values`, `n_values` | Complete | R/find_taxonomy_conflicts.R |
| `is_plausible_binomial()` | Filter out "sp.", "cf.", "aff.", uncultured, environmental, and non-binomial names; vectorised logical return | Complete | R/is_valid_species_name.R |
| `to_faire()` | Export a TaxaID data frame (match/likelihood/posterior object) to FAIRe checklist column conventions (`taxaRaw` / `taxaFinal`). Renames `observation_id` → `seq_id`, `taxon_name` → `scientificName`, etc.; constructs `verbatimIdentification`, `specificEpithet`, `checkls_ver`. Columns not in the FAIRe mapping are retained unchanged. Attaches `faire_table` attribute. | Complete | R/to_faire.R |
| `format_dwc()` | Apply per-column DarwinCore formatting rules | Planned | — |
| `validate_dwc()` | Read-only QC after formatting | Planned | — |
| `dwc_map()` | Compare input column names against full DarwinCore term list; propose `col_map` via fuzzy matching or LLM API | Planned | — |

### Cache utilities (2026-09-04)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `list_cache_files()` | Scan `cache_dir` and return every file whose basename matches any of `patterns` (regex, OR'd), with `path`/`size_mb`/`mtime` -- the generic building block behind a downstream package's own `<pkg>_clear_cache()` helper. Zero rows if `cache_dir` has no matching files or doesn't exist. | Complete | R/cache_utils.R |
| `report_and_clear_cache()` | Shared "apply an age filter, print a summary, delete or dry-run report" engine, given an already-built `inv` (typically from `list_cache_files()`, with any package-specific pre-filtering already applied -- e.g. TaxaFetch's own orphan detection). `label` names the calling function in every message. Used by `TaxaFetch::taxafetch_clear_cache()` and `TaxaLikely::taxalikely_clear_cache()`; deliberately fits only the "directory of many small, deterministically-keyed files" cache shape, not TaxaMatch's cumulative row-level-TTL reference-evaluation cache (checked directly, left untouched). | Complete | R/cache_utils.R |

### Rank and barcode utilities (Sessions 56-57)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `standard_ranks` | Character vector: `c("kingdom","phylum","class","order","family","genus","species")` | Complete | R/rank_utils.R |
| `extended_ranks` | Character vector: standard + subspecies, variety, form | Complete | R/rank_utils.R |
| `detect_ranks()` | Auto-detect which rank columns exist in a data frame; returns coarse-to-fine character vector | Complete | R/rank_utils.R |
| `barcode_length_defaults` | Named list of 12 barcode markers → `list(min, max)` bp ranges. MiFish range: `c(130L, 210L)` (tightened Session 116 from c(100L,600L); excludes bacterial cross-amplification at ~256bp). | Complete | R/barcode_utils.R |
| `resolve_barcode_marker()` | Resolve a registered primer-variant term (`"COI-Folmer"`, `"16S-Palumbi"`, `"rbcLa"`, `"cytb-Kocher"`, `"matK-Kim"`, `"trnL-Taberlet"`) to the marker it amplifies, for building a database query -- no GenBank record is tagged "Folmer", so a variant-named search matches nothing, SILENTLY. Identity for unrecognised terms; MiFish deliberately not remapped. | Complete | R/barcode_utils.R |
| `resolve_barcode_lengths()` | Resolve min/max bp from `barcode_term` vector; takes union across multiple terms; user overrides | Complete | R/barcode_utils.R |
| `barcode_primer_defaults` | Named list of primer sets → `list(fwd, rev, amplicon_range)`. Requires the *specific* primer variant (e.g. `"mifish-u"`), unlike `barcode_length_defaults`'s generic marker keys -- different variants can have genuinely different primer sequences. **Session 140**: MiFish-U, MiFish-E (12S; Miya et al. 2015). **Session 141**: 6 more entries added, one per mitochondrial/chloroplast marker in `barcode_length_defaults` -- `16s-palumbi` (Palumbi 16Sar-L/16Sbr-H), `coi-folmer` (Folmer et al. 1994 LCO1490/HCO2198; documented invertebrate-only scope, empirically confirmed to fail on human/vertebrate COI at default mismatch tolerance), `cytb-kocher` (Kocher et al. 1989 L14841/H15149), `rbcla` (Levin 2003 rbcLa-F / Kress & Erickson 2007 rbcLa-R), `matk-kim` (Hollingsworth et al. 2009 matK-3F_KIM/matK-1R_KIM), `trnl-taberlet` (Taberlet et al. 2007 primers g/h). Nuclear markers (18S, ITS/ITS2) deliberately still unpopulated -- no single canonical primer pair exists to verify for either. Every Session 141 entry was empirically tested with `Biostrings::matchPattern()` against a real GenBank mitogenome or chloroplast genome, not just cross-checked against literature -- see that session's note for two real errors this caught. **Session 142**: `coi-leray` added (mlCOIintF/dgHCO2198, Leray et al. 2013 / Meyer 2003) -- the actual eDNA/metabarcoding-relevant COI mini-barcode, distinct from `coi-folmer`'s full-length Sanger-era product. Deliberately pairs Leray's forward primer with Meyer's *inosine-free* degenerate reverse primer rather than Geller et al. (2013)'s `jgHCO2198`, which uses inosine (a base analog `Biostrings::DNAString` cannot represent) -- confirmed via a real published precedent for this exact pairing, not invented. Empirically confirmed on real *Drosophila melanogaster* mtDNA: 365bp full product, which exactly reconciles to the ubiquitous "313bp Leray fragment" figure once both primers (52bp combined) are excluded. Bare `"COI"` is now deliberately ambiguous between `coi-folmer` and `coi-leray` (same ambiguity-over-guessing discipline as MiFish-U/E). | Complete (incremental) | R/barcode_utils.R |
| `resolve_barcode_primers()` | Resolve `fwd`/`rev`/`amplicon_range` from a specific `barcode_term`. Errors (does not guess) on an ambiguous bare term (e.g. `"mifish"` alone) or an unregistered marker, with guidance to supply primers directly or pre-trim with CRABS. | Complete | R/barcode_utils.R |

### LLM provider functions (moved from TaxaFetch, Session 28)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `call_api()` | Generic, provider-neutral LLM dispatcher (Session 87) -- resolves provider/model/API key/endpoint and submits one prompt string; every `call_*_api()` provider function below is a thin wrapper around it. Also the default `llm_fn` most of this ecosystem's LLM-calling functions fall back to via `getOption("TaxaID.llm_fn")`. Handles token-usage accounting (auto-populates `token_usage()`'s ledger), `max_input_tokens` pre-flight guard, `images` (base64 PNG vision input), `show_tokens`. **2026-09-04 fix**: was undocumented in this table since Session 87 despite being this package's central dispatch function -- added during the ecosystem-wide Function Inventory accuracy pass. | Complete | R/call_api.R |
| `call_anthropic_api()` | Submit one prompt string to Anthropic Claude | Complete | R/llm_api_utils.R |
| `call_gemini_api()` | Submit one prompt string to Google Gemini (free tier available) | Complete | R/llm_api_utils.R |
| `call_openai_api()` | Submit one prompt string to OpenAI ChatGPT | Complete | R/llm_api_utils.R |
| `call_ollama_api()` | Submit one prompt string to a local Ollama model (no API key) | Complete | R/llm_api_utils.R |
| `call_azure_openai_api()` | Submit one prompt string to a DOI-internal Azure OpenAI Chat Completions endpoint (DOI employees only -- requires DOI network/VPN + `AZURE_OPENAI_API_KEY`). Thin wrapper around `call_api()`, drop-in `llm_fn`. **2026-09-04 fix**: missing from this table since it was added; found during the ecosystem-wide accuracy pass. | Complete | R/llm_api_utils.R |
| `prompt_api()` | Multi-chunk llm_prompt dispatcher; default `llm_fn` from `getOption("TaxaID.llm_fn")` | Complete | R/llm_api_utils.R |
| `prompt_manual()` | Write prompt files for manual web interface submission | Complete | R/llm_api_utils.R |
| `read_llm_response()` | Read and concatenate saved LLM response files | Complete | R/llm_api_utils.R |
| `%||%` | Null-coalescing operator; exported for use by downstream packages via `@importFrom` | Complete | R/llm_api_utils.R |

### Model registry & discovery functions (undocumented gap, added 2026-09-04)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `list_models()` | List current tier -> model-ID assignments per provider (lazy-discovered on first real use, cached locally). | Complete | R/model_registry.R |
| `refresh_models()` | Force re-discovery of available models from each provider's live API, refreshing the local persistent model cache. Call when a model name becomes stale. | Complete | R/model_registry.R |
| `set_model()` | Pin a specific model version for a given provider/tier for reproducibility (session-only, does not touch the persistent cache). | Complete | R/model_registry.R |
| `model_cache_info()` | Report the location and age of the local persistent model-discovery cache. | Complete | R/model_registry.R |
| `register_provider()` | Register a custom OpenAI-compatible LLM provider (e.g. xAI/Grok) so it can be selected via `call_api(provider = ...)`. | Complete | R/model_registry.R |

### LLM provider auto-detection (Session 82)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `.onAttach()` | On `library(TaxaTools)`: scans `~/.Renviron` for API keys, sets `options(TaxaID.llm_fn)` to the detected provider function. Priority: Anthropic > Gemini > OpenAI. Skips in non-interactive sessions; respects pre-set option. | Complete | R/zzz.R |
| `.detect_llm_provider()` | Internal: returns list of available providers (key present in env vars) | Complete | R/zzz.R |

**Behaviour:**
- **0 keys found:** startup message with setup instructions (including Ollama as local option)
- **1 key found:** auto-sets `options(TaxaID.llm_fn = <provider>)`, prints provider name
- **2+ keys found:** auto-selects first by priority, prints all available + how to switch
- All `llm_fn` defaults across the ecosystem use `getOption("TaxaID.llm_fn", <fallback>)`

### GBIF backbone census (Session 77)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `census_genus_species()` | Enumerate described species per genus (or higher rank) via GBIF backbone `name_usage(children)`. `match_species` param computes reference completeness: "complete" / "singleton_missing" / "incomplete". Higher-rank recursion (family → genera → species). `rgbif` in Suggests. | Complete | R/census_genus_species.R |

### Interactive spatial gadget (Session 134b, moved from TaxaFetch)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `define_search_polygon()` | Interactive Shiny gadget: user drags corner markers on a leaflet map to define a custom polygon. Add Point inserts a vertex at the midpoint of the longest side; Remove Last Point undoes the last add (initial corners protected); Done returns a WKT POLYGON string. Requires `shiny`, `miniUI`, `leaflet` (checked at runtime). Must be run in an interactive R session. Shared by two callers: `TaxaFetch`'s search-area use (`fetch_gbif_occurrences()`/`download_gbif_occurrences()` geometry) and `TaxaMatch::group_observations_by_bbox()`'s spatial-group use -- the only generalization either needed was the `points`/`group_col`/`init_polygon` params below. `points` (data frame with `lat`/`lng`) overlays reference markers. `group_col` (Session 134b): optional column in `points` used to color the overlay by an existing group (e.g. `spatial_group_id`), with a legend -- lets a user drawing a broader search area see which points already belong to which group. `init_polygon` (Session 134b): reopen a previously returned WKT polygon for reshaping instead of starting from a fresh square -- used by `group_observations_by_bbox()`'s end-of-loop edit step. `viewer` (Session 134b): defaults to `shiny::paneViewer(minHeight = 500)` -- **not** `shiny::dialogViewer()`, which was found via real live-testing to silently swallow the Done button's return value whenever this gadget's leaflet map is present (confirmed reproducible; see Session 134b note below for the full debugging record). `paneViewer()` matches the call style already used by `TaxaHabitat::review_spatial_flags()` and `TaxaExpect::plot_theta_map_interactive()`, so all of this ecosystem's mapping gadgets now behave consistently. `browserViewer()` also confirmed working, for callers who want a separate browser tab instead. Internal helpers `.pts_to_wkt()`/`.wkt_to_pts()` are pure and unit-tested without a live gadget session. **Session 139:** `title`/`done_label`/`cancel_label` params added (backward-compatible defaults: `"Define Search Polygon"`/`"Done"`/`"Cancel"`, unchanged from before) so a caller embedding this gadget in a larger interactive workflow can describe what each button actually does in that context, and show which specific group/area is being drawn directly in the title rather than only in a separate console message -- prompted by the user hitting real confusion live (accepting the gadget's un-shrunk starting box, reading "Done" as "confirm and proceed," merged far more observations into one group than intended). Initial zoom is also now one step further out than an exact fit, so the starting square's corners are comfortably visible/draggable on first open rather than at or beyond the frame edge. | Complete | R/define_search_polygon.R |

### Common name utilities (Session 97)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `common_to_scientific()` | Convert a character vector of common names to scientific names via LLM, with optional backbone verification via `verify_taxon_names()`. Params: `taxonomic_group`, `location`, `verify`, `backbone_id`, `llm_fn`. Returns data frame with `common_name`, `scientific_name`, `verified`, `matched_name`. | Complete | R/common_names.R |
| `fill_higher_ranks()` | Given a character vector of taxon names (typically species binomials), extract `genus` and look up `family` via a priority chain: (1) local data frames (`local_sources`), (2) primary backbone via `verify_taxon_names()` at genus level (`backbone_id = 4L`), (3) fallback backbone (`fallback_backbone_id = 11L`). Returns tibble with `taxon_name`, `genus`, `family`; warns for unresolved taxa. **2026-07-25**: `genus` is now corrected to the backbone's resolved name (not just the locally-extracted query genus) whenever an API lookup shows it's a taxonomic synonym at genus rank -- keeps this function consistent with `convert_taxonomy_backbone()`'s current-name preference, closing a real gap that silently broke `TaxaAssign::join_priors()`'s exact-string genus/family match. Backward compatible when `verify_fn`'s response lacks `matched_rank`. Internal helpers: `.build_genus_family_lookup()`, `.lookup_family_from_backbone()`, `.extract_classified_rank()`. | Complete | R/fill_higher_ranks.R |
| `escalate_taxonomic_rank()` | The escalation-ladder function (Session 137 reentry plan, Phase 1): given `taxon_name` at `current_rank`, resolves its full classification via `verify_taxon_names()` and returns the name at the next coarser rank in `rank_system` (default `standard_ranks`) -- e.g. broadening a genus with no reference sequences/occurrence records to its family. Walks up to `max_levels` (default `2L`) rank levels within one call if an intermediate rank is itself absent from the classification path (e.g. genus straight to order when family is missing), so callers get one escalation step per retry-loop iteration rather than a fixed single-rank hop. Same primary/fallback backbone pattern as `fill_higher_ranks()` (`backbone_id = 4L` NCBI, `fallback_backbone_id = 11L` GBIF). Returns `list(taxon_name, rank)`, both `NA` if already at the coarsest rank or nothing resolves within `max_levels`. Only walks the hierarchy -- has no notion of whether a fetch at any rank returned data; that's the caller's retry loop. Live-verified against real NCBI data for the PtConception 12S validation cases (*Rhacochilus*, *Embiotoca caryi* -> family `Embiotocidae`) and the bobcat-photo case (*Lynx* -> family `Felidae`). | Complete | R/escalate_taxonomic_rank.R |
| `parse_classification_path()` | Extract one rank value from the pipe-delimited `classification_path` and `classification_ranks` columns returned by `verify_taxon_names()`. Params: `path`, `ranks`, `target_rank`. Returns `NA_character_` if rank absent. Thin wrapper around `.extract_classified_rank()`; use with `mapply()` for column-level parsing. | Complete | R/fill_higher_ranks.R |
| `scientific_to_common()` | Convert scientific names to English common names. Backbone sources: GBIF (backbone_id=11, via rgbif) or ITIS (backbone_id=3, via taxize). LLM fallback when backbone returns nothing or backbone_id=NULL. `location` param biases LLM toward regionally appropriate names. Batches LLM calls (20/batch). Returns `scientific_name`, `common_name`, `common_name_alternatives` (semicolon-delimited), `source` ("gbif"/"itis"/"llm"/"none"), `backbone_id`. | Complete | R/common_names.R |

### LLM text generation functions (Session 55)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `token_usage()` | Return accumulated LLM token records as data frame. `by` param: "call" (per-call detail), "function" (totals per caller), "provider", "session" (grand total). Optional `cost_per_1k_input`/`cost_per_1k_output` adds `cost_usd` column. Auto-populated by `call_api()` — no changes needed in downstream packages. | Complete | R/token_usage.R |
| `reset_token_usage()` | Clear the session token ledger. Call before a workflow step for per-step accounting. | Complete | R/token_usage.R |
| `build_report_context()` | Domain-agnostic S3 context object with verified facts for grounding LLM output | Complete | R/draft_text.R |
| `draft_methods_text()` | Read R code and draft Methods section via LLM; context-aware; audience param | Complete | R/draft_text.R |
| `draft_results_text()` | Read R objects and draft Results section via LLM; context-aware; audience param | Complete | R/draft_text.R |

### Report section assembly functions (undocumented gap, added 2026-09-04)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `new_report_section()` | Constructor for the `report_section` S3 class used by every package's own `report_*()` function (e.g. `TaxaFetch::report_fetch()`, `TaxaMatch::report_match()`) -- one section per pipeline step, holding methods/results text, citations, params, statistics. Has `print.report_section()`/`format.report_section()` S3 methods (registered, not separately exported). | Complete | R/report_section.R |
| `assemble_report()` | Combine any number of `report_section` objects (typically one per TaxaID package used in a pipeline) into one unified markdown report, ordered by pipeline position, with deduplicated citations collected into a trailing "Data Sources" section. | Complete | R/report_section.R |

---

## Typical Workflow

```r
rename_cols()           # align column names to DarwinCore
  → create_taxon_names()   # derive best taxon name per row
  → clean_taxon_names()    # deduplicate & clean for API
  → verify_taxon_names()   # check against backbone via API
  → change_backbone()      # reshape into wide taxonomy table
```

---

## Test Coverage

| File | Functions covered | Notes |
|---|---|---|
| test-cache_utils.R | `list_cache_files()`, `report_and_clear_cache()` | **2026-09-04, new file**. Fully offline. Covers pattern matching, empty/nonexistent directories, argument validation, dry-run vs. real deletion, `older_than_days` filtering, and that `label` appears in every message |
| test-verify_taxon_names.R | `verify_taxon_names()` | Offline validation + online API tests (skipped offline) |
| test-create_taxon_names.R | `create_taxon_names()` | Fully offline |
| test-clean_taxon_names.R | `clean_taxon_names()` | Fully offline |
| test-change_backbone.R | `change_backbone()` | Fully offline; uses mock verified tibbles |
| test-rename_cols.R | `rename_cols()` | Fully offline |
| test-to_faire.R | `to_faire()` | Fully offline; 52 tests covering renames, constructed columns, attribute, missing-column handling, validation |
| test-common-names.R | `common_to_scientific()`, `scientific_to_common()` | Offline; backbone calls mocked via `local_mocked_bindings()`; location param verified via prompt capture; 52 tests |
| test-fill_higher_ranks.R | `fill_higher_ranks()`, `.build_genus_family_lookup()`, `.lookup_family_from_backbone()`, `.extract_classified_rank()` | Fully offline (API mocked); 35 tests |
| test-escalate_taxonomic_rank.R | `escalate_taxonomic_rank()` | Fully offline (API mocked); 35 tests; covers immediate-parent escalation, skip-level escalation within `max_levels`, already-coarsest short-circuit, primary/fallback backbone, custom `rank_system` |
| test-token_usage.R | `token_usage()`, `reset_token_usage()` | Fully offline; mocks `.token_ledger` directly |
| test-rank_utils.R | `standard_ranks`, `extended_ranks`, `detect_ranks()` | Fully offline |
| test-barcode_utils.R | `barcode_length_defaults`, `resolve_barcode_lengths()`, `barcode_primer_defaults`, `resolve_barcode_primers()` | Fully offline |
| test-null_coalesce.R | `%\|\|%` | Fully offline |
| test-call_api.R | `call_api()` | 21 tests; fully offline; covers input validation, `max_input_tokens` pre-flight guard, no-provider error, mocked anthropic/gemini/openai_compat response parsers, token attribute, `show_tokens` |
| test-find_taxonomy_conflicts.R | `find_taxonomy_conflicts()` | 13 tests; fully offline; covers clean data, known genus-family conflict, explicit and auto-detected rank_system, NA row skipping, multi-level conflict, output column types |
| test-is_plausible_binomial.R | `is_plausible_binomial()` | 14 tests; fully offline; covers well-formed binomials, lowercase genus, genus-only, sp./cf./aff. suffixes, uncultured/environmental/metagenome names, vectorisation, NA |
| test-llm_utils.R | `call_anthropic_api()` and other provider functions | Online tests skipped; pre-existing WARN in check |
| test-census_genus_species.R | `census_genus_species()` | Online (GBIF) tests skipped offline |
| test-draft_text.R | `build_report_context()`, `draft_methods_text()`, `draft_results_text()` | LLM calls skipped offline |
| test-model_registry.R | Model registry internals | Fully offline |
| test-report_section.R | Report section helpers | Fully offline |
| test-define_search_polygon.R | `.pts_to_wkt()`, `.wkt_to_pts()` | 8 tests; fully offline; the gadget itself requires a live interactive session and is not covered |

**Testing rules:** All tests use small inline data. No external files. No API calls except
the online group in test-verify_taxon_names.R (guarded by `skip_if_offline()`).

---

## Key Dependencies

| Package | Used for |
|---|---|
| httr | Global Names Verifier API requests |
| httr2 | LLM provider API calls (Anthropic, Gemini, OpenAI, Ollama) |
| jsonlite | JSON encoding for API body |
| dplyr | Tibble construction, data manipulation |
| tidyr | `unnest_wider()` in `change_backbone()` |
| purrr | `map2()` in `change_backbone()` |
| stringr | String cleaning in `clean_taxon_names()` |
| rlang | NSE (`:=`, `sym()`) in `change_backbone()` |
| stats | `setNames()` in `change_backbone()` |
| shiny (Suggests) | `define_search_polygon()` interactive gadget (Session 134b, moved from TaxaFetch) |
| miniUI (Suggests) | `define_search_polygon()` gadget UI (Session 134b) |
| leaflet (Suggests) | `define_search_polygon()` map rendering (Session 134b) |

---

## Design Notes
- All functions are general-purpose — no assumptions about TaxaMatch/TaxaExpect input formats
- Argument names must be consistent and intuitive (these are the most-called internal functions)
- `verify_taxon_names()` is slow for large lists — always run on a deduplicated vector, save result, load in downstream scripts
- `clean_taxon_names()` strips brackets BEFORE the capital-letter filter (bug fix Session 27)


## Renaming Log

| Old Name | New Name | Date | Notes |
|---|---|---|---|
| `f_spellcheck_sci_names` | `verify_sci_names` | 2026-02-18 | — |
| `verify_sci_names` | `verify_taxon_names` | 2026-03-26 | Consistency with package naming |
| `create_taxon_name` | `create_taxon_names` | 2026-03-26 | Plural for consistency |

---

## Session Notes

**Session 142 (2026-07-06): coi-leray added -- the actual eDNA mini-barcode, resolving Session 141's flagged inosine blocker**

Direct same-day follow-on. Session 141 left the Leray et al. (2013) mini-barcode
(mlCOIintF/jgHCO2198, the "313bp Leray fragment" widely used in real metabarcoding --
as opposed to `coi-folmer`'s full-length Sanger-era product) explicitly unimplemented,
because Geller et al. (2013)'s `jgHCO2198` reverse primer encodes several positions
with inosine (dITP), a base analog with no representation in
`Biostrings::DNAString`'s IUPAC alphabet. The user asked to learn more about the
mini-barcode's known discriminatory-power limitations and to weigh that against the
implementation difficulty before deciding whether to add it.

**Literature review (not independently re-verified against primary sources the way the
Session 141 primer sequences were -- this is background context, not a citation-grade
claim)**: shorter COI fragments carry fewer phylogenetically informative sites than the
full ~658-710bp Folmer barcode, and resolve species less reliably as a direct
consequence -- one comparison found a 313bp fragment resolved 95% of species via
barcode-gap analysis versus 87% for a much shorter (55bp) mini-barcode, i.e. a real but
bounded cost that scales with fragment length, not an unusable degradation. A second,
mechanistically distinct problem shows up in "Know your limits" (miniCOI metabarcoding
of marine zooplankton, *J. Plankton Res.*): real primer-binding-site sequence variation
causes outright non-amplification in specific taxa (Appendicularia; some *Oithona
similis* lineages show up to 6 mismatches to `mlCOIintF`) -- a property of the specific
primer sequence chosen, not of fragment length per se, and only partially mitigated by
the more-degenerate "Leray-XT" primer variant (not implemented here).

**The inosine blocker turned out to be avoidable, not fundamental.** `mlCOIintF`
itself is already fully IUPAC-standard (only `W`/`Y` degeneracy, no inosine) --
only Geller's redesigned reverse primer has the problem. Real precedent exists for
pairing `mlCOIintF` with **Meyer (2003)'s `dgHCO2198`** instead -- a fully degenerate,
inosine-free encoding of the same reverse-primer binding site (Gomez-Rodriguez et al.,
"Biases in bulk", *Molecular Ecology* 2020, use exactly this pairing) -- so no lossy
N-substitution approximation was needed. `dgHCO2198` cross-checked against two
independent sources (`TAAACTTCAGGGTGACCAAARAAYCA`, differing from `coi-folmer`'s
`HCO2198` only in two ambiguity-coded positions). Empirically confirmed against the
real *Drosophila melanogaster* mitogenome (NC_001709.1, the same accession Session 141
used for `coi-folmer`): unique hit at positions 1834-2198, a 365bp full PCR product.
365 minus both primers' combined length (52bp) is exactly 313bp -- this cleanly
reconciles the measurement with the "313bp Leray fragment" figure ubiquitous in the
metabarcoding literature (which refers to the primer-excluded interior), the same
primer-inclusive-vs-exclusive distinction already noted for `coi-folmer`'s 710bp.

`coi-leray` added to `barcode_primer_defaults` (`fwd = "GGWACWGGWTGAACWGTWTAYCCYCC"`,
`rev = "TAAACTTCAGGGTGACCAAARAAYCA"`, `amplicon_range = c(350L, 370L)`). Bare `"COI"`
is now deliberately ambiguous between `coi-folmer` and `coi-leray` --
`resolve_barcode_primers("COI")` errors rather than guessing, same discipline as
MiFish-U/E, forcing the caller to specify which fragment their actual data is.

7 new/updated tests: `coi-folmer` vs `coi-leray` distinguished; the new bare-`"COI"`
ambiguity error; one existing test that had assumed bare `"COI"` resolved uniquely
(it previously did, before this session) updated to `"COI-Folmer"` explicitly.
`devtools::document()` + `devtools::test()` (129/129 in `test-barcode_utils.R`, full
suite unaffected) + `devtools::check()` (0 errors, 0 warnings, 0 notes) all clean.
See `TaxaLikely/CLAUDE.md`'s own Session 142 note for the consuming-side tests
(`trim_to_amplicon()` correctly extracts a real Leray-fragment amplicon).

**Session 141 (2026-07-06): barcode_primer_defaults expanded to every mito/chloroplast marker -- empirical verification catches two real errors**

Follow-on the same day as Session 140. After that session shipped `trim_to_amplicon()`
scoped to MiFish-12S only, the user asked directly: is primer-based amplicon trimming
actually worth it for 12S specifically, or better to just drop over-length sequences? --
and separately, to work through the rest of the mitochondrial and chloroplast markers in
`barcode_length_defaults` (explicitly told to skip the nuclear genes -- 18S/ITS/ITS2 --
since those don't have one canonical primer pair the way mito/chloroplast genes do).

**Opinion on 12S given first**: yes, practical, for three reasons -- the fallback is
always exactly today's length-exclusion behavior (never removes a sequence that would
otherwise be kept), the primer specificity plus length-plausibility gate make a spurious
accept astronomically unlikely, and the problem is already observed on real data (Session
139's "No H1 pairs found" bug), disproportionately affecting exactly the rare/undersampled
species this pipeline cares most about.

**Six new entries added**, each verified two ways -- cross-checked against 2-3 independent
sources (ideally the primary paper), AND empirically tested with
`Biostrings::matchPattern()` against a real GenBank sequence (a real mitogenome for
mitochondrial markers, a real chloroplast genome for plastid markers) -- fetched live via
NCBI eutils rather than relying on citation text alone:

- `16s-palumbi` (16Sar-L/16Sbr-H, Palumbi 1996) -- confirmed 590bp on real human mtDNA
  (NC_012920.1).
- `coi-folmer` (LCO1490/HCO2198, Folmer et al. 1994) -- sequences read directly from a
  fetched copy of the primary 1994 paper. Confirmed on real *Drosophila melanogaster*
  mtDNA (NC_001709.1) at **exactly** positions 1490-2198 (matching the primers' own
  position-based names) with a 709bp amplicon (paper reports 710bp). Also confirmed,
  empirically, a real documented limitation: at `max_mismatch_rate` ~0.12-0.15 this pair
  does NOT match human/vertebrate COI -- consistent with the paper's own invertebrate-only
  design scope and the reason Geller et al. (2013) later redesigned it for broader
  taxonomic coverage.
- `cytb-kocher` (L14841/H15149, Kocher et al. 1989) -- **caught a real error this way**:
  two independent secondary sources both stated a 309bp amplicon; direct empirical testing
  against real human mtDNA measured 358bp. A third secondary source's "359bp" was
  essentially confirmed (within 1bp). Used the primers' core annealing sequence only --
  some secondary sources report versions with a 5' restriction-site cloning tail
  (`AAAAAGCTT`/`AAACTGCAG`) that isn't part of the genomic template and would never match
  a real sequence.
- `rbcla` (rbcLa-F/rbcLa-R, Levin 2003 / Kress & Erickson 2007) -- cross-checked against
  the Canadian Centre for DNA Barcoding's own "Primer Sets for Plants and Fungi" protocol
  PDF (a primary protocol document, not a citing paper) plus two further sources; confirmed
  599bp on real *Arabidopsis thaliana* chloroplast DNA (NC_000932.1). Noted, not silently
  reconciled: this real measurement does NOT match the "~670bp" figure commonly quoted for
  "the rbcLa barcode" elsewhere -- that figure likely refers to a longer product using the
  alternative `rbcLajf634R` reverse primer (Fazekas et al. 2008), which isn't implemented.
- `matk-kim` (matK-3F_KIM/matK-1R_KIM, Hollingsworth et al. 2009 CBOL, attributed to K-J
  Kim) -- **caught a second real error, resolved empirically rather than guessed**: most
  sources describe 3F_KIM as forward and 1R_KIM as reverse, but the CCDB's own protocol PDF
  labels them the opposite way in its "-f"/"-r" suffixes. Tested both orientations directly
  against the real *Arabidopsis* chloroplast genome: `3F_KIM` matched upstream on the sense
  strand (true forward), `1R_KIM`'s reverse complement matched downstream (true reverse) --
  874bp amplicon, consistent with this pair's commonly-cited ~850bp product.
- `trnl-taberlet` (primers g/h, Taberlet et al. 2007) -- sequences read directly from the
  primary paper's own Table 1 (fetched via PMC). Confirmed 87bp on real *Arabidopsis*
  chloroplast DNA, within the paper's own documented 10-143bp P6-loop range across land
  plants (a highly length-variable marker by design -- this is its intended discriminatory
  signal, not primer-matching noise).

**Deliberately still not populated**: 18S, ITS, ITS2 -- explicitly out of scope per the
user's own instruction this session, since none of these has one single canonical primer
pair the way every mito/chloroplast marker checked here does (matches the reasoning already
recorded for 18S in Session 140's note).

8 new offline tests (`test-barcode_utils.R`) covering unambiguous bare-marker-name
resolution (`"16S"`, `"COI"`, `"cytb"`, `"rbcL"`, `"matK"`, `"trnL"` each resolve uniquely
despite the registry's specific-variant keys, since only one variant per marker is
registered). One existing test updated: the "unregistered marker" example switched from
`"COI"` (now registered) to `"ITS2"`. `devtools::document()` + `devtools::test()`
(119/119 in this file, full suite unaffected) + `devtools::check()` (0 errors, 0 warnings,
0 notes) all clean.

**Session 140 (2026-07-06): barcode_primer_defaults + resolve_barcode_primers() -- new primer registry for TaxaLikely::trim_to_amplicon()**

Companion to `TaxaLikely::trim_to_amplicon()` (in-silico PCR amplicon extraction, see
that package's own Session 140 note and
`ecosystem_docs/REENTRY_PROMPT_session139_insilico_pcr_amplicon_trimming.md` for the
full design discussion). This package's half: a new primer-sequence registry mirroring
`barcode_length_defaults`'s shape but with a deliberately different matching contract.

**Why matching can't mirror `resolve_barcode_lengths()` exactly**: that function
resolves a bare `"mifish"` to a merged length range covering both MiFish-U and
MiFish-E, which is safe because their amplicon lengths overlap closely (163-185bp vs.
170-185bp). Primer *sequences* can't be merged the same way -- U and E are genuinely
different oligos. `resolve_barcode_primers()` therefore requires the specific variant
(`"MiFishU"`/`"mifish-u"`/`"MIFISH_U"`, case/separator-insensitive) and **errors rather
than guessing** when a bare `"mifish"` matches more than one registered variant, or when
the term isn't registered at all -- both error messages point the caller at supplying
`primer_fwd`/`primer_rev` directly or pre-trimming with CRABS.

**Primer sequences verified against three independent sources** before being added
(Miya et al. 2015's own text, a university eDNA core-facility protocol page, and a
GitHub pipeline README all agreed verbatim) -- not trusted from training-data memory
alone, given a wrong base in a primer sequence would silently corrupt real reference
data downstream. MiFish-U-F `GTCGGTAAAACTCGTGCCAGC` / MiFish-U-R
`CATAGTGGGGTATCTAATCCCAGTTTG`; MiFish-E-F `GTTGGTAAATCTCGTGCCAGC` / MiFish-E-R
`CATAGTGGGGTATCTAATCCTAGTTTG`.

**Deliberately not populated**: every other marker in `barcode_length_defaults` (16S,
COI, cytb, ITS/ITS2, rbcL, matK, 18S, trnL, teleo) has no entry here yet. 18S in
particular was explicitly considered and rejected -- unlike MiFish, there is no single
canonical 18S primer pair (`barcode_length_defaults`'s own existing comment already
notes 18S "varies widely by primer set"), so inventing one entry would misrepresent a
marker that doesn't have one standard answer. Only MiFish-U/E were added because they
are (a) the only marker with real production use in this ecosystem's workflows
(confirmed by grep across `TaxaLikely/inst/workflows/`) and (b) verifiable against a
single canonical source. Registry is designed to grow incrementally, same pattern as
`barcode_length_defaults` itself.

8 new offline tests (`test-barcode_utils.R`): exact/case/separator-insensitive matching,
MiFish-U vs. MiFish-E distinction, the deliberate ambiguous-bare-term error, unregistered-marker
error, and input validation. `devtools::document()` + `devtools::test()` (77/77 in this
file, full suite unaffected) + `devtools::check()` (0 errors, 0 warnings, 0 notes) all clean.

**Session 139 (2026-07-06): define_search_polygon() usability redesign -- customizable title/button labels, zoomed-out initial view**

Branch `main`. Prompted directly by the user hitting real confusion while live-testing
`TaxaMatch::group_observations_by_bbox()` (see that package's own Session 139 note for the
full spatial-grouping redesign this was part of): clicking the gadget's generic "Done"
button on its un-shrunk starting square (which is deliberately oversized to guarantee it
encloses every point) merged far more observations into one group than intended, because
nothing in the UI signals that the starting box is meant to be resized first -- "Done"
reads as "confirm and proceed," not "I've finished positioning this."

Added `title`/`done_label`/`cancel_label` parameters, all backward-compatible (defaults
unchanged: `"Define Search Polygon"`/`"Done"`/`"Cancel"`, matching this function's
behavior before this session for any caller that doesn't pass them). Wired via
`miniUI::gadgetTitleBar(title, left = miniUI::miniTitleBarCancelButton(label =
cancel_label), right = miniUI::miniTitleBarButton("done", done_label, primary = TRUE))`
-- confirmed `miniTitleBarCancelButton()`'s own signature (`inputId = "cancel", label =
"Cancel", primary = FALSE`) directly rather than assuming it, since the existing server
code's `observeEvent(input$cancel, ...)` handler depends on `inputId` staying `"cancel"`
regardless of the displayed label. `TaxaMatch::group_observations_by_bbox()` now passes
context-specific wording ("Group These Points"/"No More Groups", with per-iteration
progress in the title) instead of relying on the generic defaults -- see that package's
own Session 139 note.

Also widened the initial zoom by one step (`round(8L - log2(view_radius_deg)) - 1L`
instead of the exact-fit `round(8L - log2(view_radius_deg))`) so the un-shrunk starting
square's corners are comfortably inside the visible frame on first open, not right at or
beyond its edge -- directly requested by the user as "the bounding box can't be seen on
first opening."

`devtools::document()` + `devtools::test()` (723 expectations, 0 failures) +
`devtools::check()` (0 errors, 0 warnings, 0 notes) all clean. No test changes needed --
the pure `.pts_to_wkt()`/`.wkt_to_pts()` helpers this package's own tests cover are
unaffected; the new params/zoom change only affect the live gadget path, which remains
outside this package's own testing boundary (requires a real interactive session).

**Session 137 (2026-07-05): escalate_taxonomic_rank() -- escalation ladder, Phase 1 of the observation-pipeline-wiring reentry plan**

Branch `single-observation-pipeline`. Per `ecosystem_docs/REENTRY_PROMPT_session137_observation_pipeline_wiring.md`, the escalation ladder (broaden genus -> family -> order when a singleton's own genus has no reference data or occurrence records) had been validated by hand three separate times (Sessions 134, 134b, 134c) but never built as a real function -- the actual bottleneck blocking the single-observation and spatially-independent multi-observation cases, not the spatial-grouping mechanism itself (that part was already done). Package placement (TaxaTools vs. TaxaLikely vs. TaxaExpect) confirmed with the user before starting: TaxaTools, matching the precedent of `%||%` and `define_search_polygon()` -- generic taxonomic-hierarchy-walking logic, not fetch-API-specific, shared by both consumers (TaxaLikely for reference-sequence fetch, TaxaExpect for occurrence fetch).

`escalate_taxonomic_rank(taxon_name, current_rank, rank_system = standard_ranks, max_levels = 2L, backbone_id = 4L, fallback_backbone_id = 11L, verbose = TRUE)` added (`R/escalate_taxonomic_rank.R`). Reuses `verify_taxon_names()` + `parse_classification_path()` directly (same primary-then-fallback-backbone pattern as `fill_higher_ranks()`) rather than duplicating classification-lookup logic. Given a taxon at `current_rank`, resolves its full classification once, then walks coarser ranks in `rank_system` starting at the immediate parent, up to `max_levels` steps, returning the first rank/name pair present in the classification path. This lets one call automatically skip a rank that's genuinely absent from the backbone's own path (e.g. genus straight to order when family isn't populated) without a second API round-trip -- distinct from "no reference/occurrence data at that rank," which is the caller's retry loop's job to detect by trying a fetch and calling this function again with the returned rank/name as the new `current_rank`/`taxon_name` if that fetch is still empty. Short-circuits with no API call at all when `current_rank` is already the coarsest rank in `rank_system`.

35 tests (`test-escalate_taxonomic_rank.R`), fully offline, `verify_taxon_names()` mocked via `local_mocked_bindings()` following `test-fill_higher_ranks.R`'s established pattern. `devtools::document()` + `devtools::test()` (723 expectations ecosystem-wide, 0 failures) + `devtools::check()` (0 errors, 0 warnings, 1 pre-existing NOTE re: cross-package Rd xrefs) all clean.

Live-verified against real NCBI data (not just mocks) for the exact validation cases named in the reentry prompt: `escalate_taxonomic_rank("Rhacochilus", current_rank = "genus")` -> family `Embiotocidae`; `escalate_taxonomic_rank("Embiotoca caryi", current_rank = "species")` -> genus `Embiotoca`; and the bobcat-photo case, `escalate_taxonomic_rank("Lynx", current_rank = "genus")` -> family `Felidae`. All three match the prior sessions' ad hoc validation.

**Not done this session** (Phases 2-7 of the reentry plan): wiring spatial grouping or this function into any of the four production workflow scripts, the Reads-table relocation, the TaxaAssign `(observation_id, site)` schema question, the end-to-end test matrix, or documentation. See the reentry prompt for the full sequenced plan.

**Session 134b (2026-07-04): define_search_polygon() moved here from TaxaFetch**

Branch `single-observation-pipeline`, follow-up to TaxaFetch/TaxaMatch's Session 134
(automatic spatial grouping). After the user reviewed that session's implementation,
a design question came up before committing: could the same interactive polygon gadget
serve both TaxaFetch's search-area purpose and TaxaMatch's new spatial-group purpose
(`group_observations_by_bbox()`), or did they need separate tools? Worked out that the
only generalization needed was small and additive -- coloring the `points` overlay by an
existing group column, and letting a previously drawn polygon be reopened for reshaping --
neither changes the core interaction model. That argued for one shared gadget rather than
duplicating it, so `define_search_polygon()` moved here (a dependency both TaxaFetch and
TaxaMatch already have) and TaxaFetch/TaxaMatch call `TaxaTools::define_search_polygon()`.

- Added `group_col` param: optional column in `points` used to color the reference-marker
  overlay by group (e.g. `spatial_group_id`), with a legend.
- Added `init_polygon` param: an existing WKT POLYGON string can be passed to reopen the
  gadget seeded with that polygon's own vertices instead of a fresh square -- used by
  `TaxaMatch::group_observations_by_bbox()`'s new end-of-loop edit step.
- Refactored `.pts_to_wkt()`/`.wkt_to_pts()` (WKT <-> vertex-vector conversion) out of the
  function's closure to module scope (`@noRd`) so they're unit-testable without a live
  gadget session -- matching the pattern the ecosystem already uses for other pure
  geometry helpers (e.g. `TaxaMatch`'s `.bbox_center_radius()`).
- `shiny`/`miniUI`/`leaflet` added to this package's `DESCRIPTION` Suggests (moved from
  TaxaFetch's, which no longer calls those namespaces directly).
- 8 new tests (`test-define_search_polygon.R`), fully offline (the gadget itself still
  requires a live interactive session, same testing boundary as before the move).
  `devtools::document()` + `devtools::test()` (688 expectations, 0 failures) +
  `devtools::check()` (0 errors, 0 warnings, 0 notes) all clean.
- See TaxaFetch/CLAUDE.md and TaxaMatch/CLAUDE.md Session 134b notes for what changed on
  the calling side, and `ecosystem_docs/REENTRY_PROMPT_session134b_grouping_implemented.md`
  for the full design discussion.

**Bug found and fixed live-testing the gadget with `points` for the first time (same
session):** the `points`/`group_col` reference-marker overlay never actually rendered --
it flashed on load and immediately vanished. Root cause: `leaflet::clearMarkers()` and
`leaflet::clearShapes()` are not scoped to the layers you just added with `addMarkers()`/
`addPolygons()` -- per the leaflet R package's own documentation, `clearMarkers()` removes
**every** marker-type layer on the map (`addMarkers()`, `addCircleMarkers()`,
`addAwesomeMarkers()` alike), and `clearShapes()` removes every polygon/line/circle layer,
regardless of which call added them. The gadget's redraw `observe()` block called both,
intending only to wipe the old draggable-vertex polygon before redrawing it -- but that
also wiped the `addCircleMarkers()` reference-point overlay added once at gadget startup,
and since that `observe()` block fires immediately on load (not just on user interaction),
the points never had a chance to stay visible. Fixed by tagging the polygon and draggable
vertices with `group = "editor"` and the reference points with `group = "reference_points"`,
then replacing the two global `clear*()` calls with a single `leaflet::clearGroup(proxy,
group = "editor")` that only touches the editor's own layers. This bug existed from the
original `points` param's introduction (TaxaFetch Session 134) -- the pure/unit-tested
helpers never exercised it, and this was the first time anyone actually ran the gadget
with `points` supplied. Re-verified: `devtools::test()` (688 expectations, 0 failures),
`devtools::check()` (0 errors, 0 warnings, 0 notes).

**Second, much larger bug found the same way (same session): RStudio's `dialogViewer()`
silently swallowed the Done button's return value for this gadget specifically.** After
the fix above, live use of `group_observations_by_bbox()` still completely failed --
clicking Done closed the dialog, but the function always behaved as if the user had
clicked Cancel (returned `NULL`), so the calling loop never recorded a polygon and never
reopened for a second box. This took an extended debugging session to isolate, because
every offline signal looked fine: the installed code was confirmed correct via
`loadNamespace()` + `deparse()` (ruling out a stale-library-cache theory that seemed very
plausible at first, given `~/.Renviron`'s `R_LIBS_USER=~/Library/R/4.0/library` -- **not**
the path documented in this file's Developer Environment table -- turned out to be the
real, active library the whole time, confirmed by starting a real `R` session from the
project directory and checking `.libPaths()`/`find.package()` directly); a minimal
`miniUI` gadget (no leaflet, just a title bar and a Done button) worked correctly with
`shiny::dialogViewer()`, ruling out a general `shiny`/`miniUI`/RStudio incompatibility;
and the actual point-in-polygon math was independently verified correct with `sf` in
isolation. The conclusive test: the *exact* production gadget code (leaflet map,
reactive observers, everything), reconstructed via `deparse()` with only
`shiny::dialogViewer(...)` swapped for `shiny::browserViewer()`, opened in a real Chrome
browser and worked perfectly on the first click -- confirmed both by inspecting the
live page (Claude's Chrome browser-automation tools: accessibility tree showed real map
tiles and a correctly-updating live WKT preview) and by the calling R session printing
the correct WKT string after the click. Root cause, narrowed to: RStudio's embedded
dialog webview specifically mishandles this gadget's Leaflet content in a way that
breaks the Done button's click-to-server round trip, while an identical non-leaflet
gadget works fine in the same viewer and this exact gadget works fine outside that one
webview. Not something this package can fix in RStudio's dialog webview -- added a
`viewer` param to `define_search_polygon()` instead of the previous hardcoded
`shiny::dialogViewer(...)`. First set to `shiny::browserViewer()` (confirmed reliable),
but the user then pointed out this ecosystem already has two other interactive mapping
gadgets (`TaxaHabitat::review_spatial_flags()`, `TaxaExpect::plot_theta_map_interactive()`)
that both use `shiny::paneViewer()` successfully -- mixing a browser-tab gadget with
pane-based ones would be a needless inconsistency for the user. Tested
`paneViewer()` directly against this exact gadget (not just the non-leaflet minimal
test) and confirmed it also round-trips Done correctly, so the **final default is
`shiny::paneViewer(minHeight = 500)`**, matching the other two gadgets' own call style
exactly. `browserViewer()` remains confirmed working and is documented as the
alternative to pass explicitly; `dialogViewer()` is documented as the one to avoid for
this function. Callers who've confirmed `dialogViewer()` works on their own machine can
still pass it explicitly. Re-verified after each change: `devtools::test()` (688
expectations, 0 failures), `devtools::check()` (0 errors, 0 warnings, 0 notes). See
`TaxaID/CLAUDE.md`'s Known R Footguns for the ecosystem-wide note (any future Shiny
gadget wrapping `leaflet` should default away from `dialogViewer()` until this is
independently reproduced/reported upstream; use `paneViewer()` for consistency with the
mapping gadgets that already exist in this ecosystem).

Sessions 27–84 archived in ecosystem_docs/session_notes/TaxaTools_sessions.md.

**Session 85 (2026-05-23)**
- `call_api()` added to `R/call_api.R`: generic LLM dispatcher. Three handler families:
  `anthropic`, `gemini`, `openai_compat`. Data-driven via `inst/model_tiers.json`.
  Attaches `model` + `provider` attributes to response.
- All five `call_*_api()` functions converted to thin wrappers around `call_api()`.
  Same signatures; HTTP logic now lives in `call_api.R`. Kept for backward compatibility.
- `options(TaxaID.provider)` new R option storing active provider name string.
  `.onAttach()` now sets both `TaxaID.provider` and `TaxaID.llm_fn = call_api`.
- `type = "openai_compatible"` → `handler_family = "openai_compat"` in `register_provider()`.
- `prompt_api()`, `draft_methods_text()`, `draft_results_text()` defaults updated to `call_api`.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes (with pre-existing WARN on test-llm_utils.R)

**Session 86 (2026-05-23)**
- No code changes. WERC peer review integration (ecosystem docs, code.json, renv removal).
- `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at TaxaID/ root).
- Disclaimer section removed from `README.md`. See TaxaID/CLAUDE.md for full log.

**Session 87 (2026-05-26)**
- `call_api()`: `images` param added (named list of base64 PNG strings, as produced by
  `.render_pdf_pages()` in TaxaFetch). Each handler family formats images in its native
  vision block format: anthropic → image content blocks (`type/source/base64`),
  gemini → `inlineData` parts (`mimeType/data`), openai_compat → `image_url` blocks
  (`data:image/png;base64,...`). Text-only calls (images = NULL) unchanged.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 113 (2026-06-19)**
- `clean_taxon_names()`: added underscore-to-space normalization for Jonah Ventures / SILVA
  pipeline names that encode binomials as `Genus_epithet`. Regex
  `^[A-Z][A-Za-z.-]+_[a-z][A-Za-z.-]*$` detects the pattern; `gsub("_", " ", ...)` converts.
  Does NOT alter OTU codes (`OTU_001`), clade codes (`MAST-4`), or multi-underscore strings.
  8 new tests in `test-clean_taxon_names.R`.
- `verify_taxon_names()`: GBIF backbone (id=11) returns `matchedName` with authority strings
  (e.g. `"Paracalanus parvus (Claus, 1863)"`). Added `strip_authority()` helper using
  `regmatches()`/`regexpr()` to extract genus + optional epithet only. Applied at parse time
  so `matched_name` is clean everywhere downstream. NCBI backbone (id=4) was unaffected.
- `devtools::check()`: 675 tests passing; 0 errors, 0 warnings, 0 notes.

**Session 106 (2026-06-10)**
- `fill_higher_ranks()` added (`R/fill_higher_ranks.R`): given a character vector of taxon
  names (typically species binomials), extracts genus (first word) and looks up family via a
  priority chain: (1) local data frames (`local_sources`), (2) `verify_taxon_names()` at
  genus level on primary backbone (`backbone_id = 4L` NCBI), (3) fallback backbone
  (`fallback_backbone_id = 11L` GBIF). Genus-level querying means species absent from a
  backbone as synonyms are still resolved if their genus is present. Returns tibble with
  `taxon_name`, `genus`, `family`; warns for unresolved taxa; preserves duplicates and order.
  Internal helpers: `.build_genus_family_lookup()`, `.lookup_family_from_backbone()`,
  `.extract_classified_rank()`.
- `parse_classification_path()` added (`R/fill_higher_ranks.R`): thin exported wrapper
  around `.extract_classified_rank()`. Parses a single rank value from the
  pipe-delimited `classification_path` / `classification_ranks` columns returned by
  `verify_taxon_names()`. Use with `mapply()` for column-level extraction. Enables
  Option C pattern: `verify_taxon_names(word(name, 1))` → `parse_classification_path()`.
- `tibble` added to `DESCRIPTION` Imports (was missing; caused R CMD check ERROR).
- 39 tests in `test-fill_higher_ranks.R` (all offline; backbone API mocked via
  `local_mocked_bindings()`).
- `devtools::check()`: vignette/Pandoc ERROR is pre-existing infrastructure issue; 0 errors
  in R code checks.

**Session 92 (2026-05-27)**
- `call_api()`: two new params + token usage reporting:
  - `show_tokens = FALSE`: when TRUE, prints `"Tokens used — input: N, output: N"` after
    each call via `message()`. Default FALSE to avoid output in batch workflows.
  - `max_input_tokens = NULL`: pre-flight guard — estimates prompt tokens as
    `ceiling(nchar(prompt_str) / 3.5)` and stops before the HTTP call if over limit.
    Provides a substitute for interactive cancellation in long-running batch loops.
  - `attr(result, "tokens")`: new attribute always attached to the returned string.
    Named list `list(input = N, output = N)` with integers from the provider's response
    body. `NA_integer_` when the provider does not report usage.
  - Internal parsers `.parse_anthropic_response()`, `.parse_gemini_response()`,
    `.parse_openai_compat_response()` now return `list(text, tokens)` instead of a bare
    string. Token field names: Anthropic `body$usage$input_tokens`/`output_tokens`;
    Gemini `usageMetadata$promptTokenCount`/`candidatesTokenCount`; OpenAI-compat
    `usage$prompt_tokens`/`completion_tokens`.
  - Provider wrapper functions (`call_anthropic_api()` etc.) unchanged — they route
    through `call_api()` and pass `...` so users can access `show_tokens`/`max_input_tokens`
    by calling `call_api()` directly.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.
