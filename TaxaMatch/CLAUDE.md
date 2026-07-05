# CLAUDE.md — TaxaMatch
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-07-05 (Session 135 — blast_sequences(resolve_location=) added to
# extract GenBank lat_lon/country qualifiers for BLAST hit accessions; closes the
# BLAST-hit-side half of the location-metadata gap flagged in ecosystem_docs/
# TODO_validation_benchmark.md's "Sourcing location data" section. See Session 135 note
# below. Session 134b — group_observations_by_bbox() moved here from
# TaxaFetch and substantially reworked (default-to-observation_id behavior, last-drawn-wins
# overlap rule, end-of-loop review/edit/delete step); new assign_spatial_group() manual
# helper; build_site_table() now populates spatial_group_id/spatial_group_N defaults on
# every row. sf added to Imports. See Session 134b note below. Session 134 — build_site_table()
# added: unified long-format site table across image/DNA/acoustic pathways, see Session 134
# note below. Session 132 — non-portable filenames from Session 129's camera-trap expansion
# fixed, see Session 132 note below.)

---

## Package Purpose
Stores and standardizes raw match data produced by external biological classification
programs (DNA barcoding pipelines, image classifiers, acoustic recognizers). Produces
a canonical match object for input to TaxaLikely.

Now also provides a complete FASTQ-to-match pipeline: ingest DADA2 sequence tables or
FASTA files, filter by length/abundance, BLAST against NCBI (remote or local), and
standardize results.

TaxaMatch does NOT perform score-to-likelihood conversion or reference quality checks —
those functions live in TaxaLikely.

**Status: All functions written and passing `devtools::check()` (0 errors, 0 warnings, 0 notes).**

---

## Dependency Chain

TaxaTools → TaxaFetch → TaxaHabitat → TaxaExpect → TaxaAssign
TaxaMatch → TaxaLikely → TaxaAssign

TaxaMatch depends on TaxaTools for `rename_cols()`, `create_taxon_names()`, and (Session
134b) `define_search_polygon()` (called by `group_observations_by_bbox()`).
Also depends on `httr2` (remote BLAST API), `rentrez` + `xml2` (taxonomy resolution), and
(Session 134b) `sf` (point-in-polygon spatial-group assignment).
`Biostrings` and `rBLAST` are in Suggests (FASTA reading and local BLAST, respectively).

---

## Match Data Sources

| Source type | Example program | Score column | Sample ID column | Reference list |
|---|---|---|---|---|
| DNA barcoding | DADA2 + BLAST | `PercMatch` (0-100) | `ESVId` | NCBI nucleotide |
| Image classifier | Animl (MegaDetector + SpeciesNet) | `confidence` (0-1) | image_id / crop_id | SpeciesNet species list (~1,295 spp) |
| Acoustic recognizer | BirdNET | `confidence` (0-1) | recording_id × detection | BirdNET species list (~6,000+ spp) |

Raw column names vary by source — `standardize_match_data()` handles the rename.

### Image classifier details (Animl — Complete)

- **R package:** `animl` on CRAN (wraps Python backend; requires Python >= 3.12)
- **Pipeline:** `detect()` (MegaDetector bounding boxes) → `classify()` (species prediction) → `sequence_classification()` (temporal refinement)
- **Output:** CSV with species, confidence, bounding boxes; multi-level taxonomy fallback (species → genus → family when confidence is low)
- **Export formats:** CSV, COCO JSON, Timelapse CSV, folder organization
- **Score interpretation:** CNN confidence (0-1); NOT comparable to BLAST % identity — requires separate likelihood model calibration in TaxaLikely
- **Ingest function:** `read_animl_output()` — implemented in `R/read_image.R` (Session 93)
- **Reference:** https://docs.animl.camera/

### Acoustic recognizer details (BirdNET — Complete)

- **Tool:** BirdNET (Cornell Lab of Ornithology); CNN-based acoustic classifier
- **Output:** CSV with start_time, end_time, scientific_name, common_name, confidence (0-1); top-N candidates per detection
- **Score interpretation:** CNN confidence (0-1); same calibration caveat as image classifiers
- **Species coverage:** ~6,000+ bird species; species list is queryable (reference DB equivalent for completeness audits)
- **R interfaces:** BirdNET-R, warbleR (acoustic analysis), or direct Python CLI
- **Ingest function:** `read_birdnet_output()` — implemented in `R/read_acoustic.R` (Session 93)
- **Reference:** https://birdnet.cornell.edu/

### Design notes for non-sequence data types

1. **Ingest functions** (`read_animl_output()`, `read_birdnet_output()`) are thin — read CSV, apply `col_map`, pass to `standardize_match_data()`. No model fitting or classification happens in TaxaMatch.
2. **Score calibration** is fundamentally different from DNA: CNN confidence is not % identity. TaxaLikely's `train_likelihood_model()` handles this — it is score-agnostic and works on any 0-1 normalised score. But the training reference for image/acoustic data is the model's own species list, not NCBI sequences.
3. **Completeness audits** query the model's known species list (not NCBI). A new `audit_model_coverage()` function in TaxaLikely (or adapted `audit_reference_coverage()`) would compare expected species against the model's taxon list.
4. **Multi-level taxonomy fallback** (Animl reports genus when unsure of species) maps directly to `taxon_name_rank` — no architecture change needed.
5. **Priority:** Secondary to sequence pipeline. Placeholder stubs now; real implementation when test data (BirdNET CSV, Animl export) are available.

---

## Canonical Match Object (output of `standardize_match_data()`)

One row per `observation_id` × reference accession match.

| Column | Renamed from | Required | Notes |
|---|---|---|---|
| `observation_id` | `ESVId` (DNA) | Yes | Unique query identifier |
| `score_original` | `PercMatch` (DNA) | Yes | Raw match score — preserved unchanged; downstream packages add `score_norm`, `score_softmax`, `score_likelihood` |
| `taxon_name` | derived | Yes | Best taxon from `create_taxon_names()` |
| `taxon_name_rank` | derived | Yes | Rank of `taxon_name` |
| taxonomy cols | `Kingdom`…`Species` | Yes | Kept as-is from source |
| `TestId` | keep | No | Marker/barcode type; not renamed, not modelled |
| `Accession` | keep | No | Reference accession; not renamed, not modelled |

**Sample context** (site, date, replicate) is stored in a separate table and joined to
likelihood output downstream — it is NOT part of the match object.

---

## Function Inventory

### Sequence input and filtering

| Function | File | Status | Description |
|---|---|---|---|
| `read_sequence_table()` | R/sequence_input.R | Written | Ingest DADA2 seqtab matrix, FASTA file, or DNAStringSet; optional taxonomy join |
| `filter_sequences()` | R/sequence_input.R | Written | Filter ASVs by length range and minimum abundance; `barcode_term` auto-detection |

### BLAST search

| Function | File | Status | Description |
|---|---|---|---|
| `blast_sequences()` | R/blast.R | Written, field-tested | Remote NCBI BLAST (httr2) or local rBLAST; score window filtering; taxonomy resolution. **Session 135**: `resolve_location = FALSE` param — when `TRUE`, fetches each unique hit accession's full GBSeq XML record (`.resolve_locations_by_acc()`) and appends `lat`/`lon`/`country` parsed from the `source` feature's `lat_lon`/`country` qualifiers (`.parse_lat_lon()`); independent of `resolve_taxonomy` (taxonomy comes from the NCBI taxonomy DB, location from the full nucleotide record — neither fetch gives you the other). |

### Image and acoustic input

| Function | File | Status | Description |
|---|---|---|---|
| `score_image_inat()` | R/score_image_inat.R | Complete | Submit image(s) directly to iNaturalist CV API; returns canonical match object. Accepts single file, file vector, or directory. Per-image EXIF lat/lng/date extraction (requires `exifr` Suggests). User-supplied `lat`/`lng`/`observed_on` override EXIF and apply to all images. Outputs `observation_id`, `taxon_name`, `taxon_name_rank`, `score_original` (= `combined_score`), `genus`, `common_name`, `iconic_taxon_name`, `taxon_id`, `n_observations`, `vision_score`, `combined_score`, `freq_score`, `geo_prior_weight` (= combined/vision), `lat`, `lng`, `observed_on`, `folder_1`/`folder_2`/... (nested path metadata). Requires `httr` (Imports), `tibble`, `dplyr`. `exifr` in Suggests. Run `convert_taxonomy_backbone()` + `fill_higher_ranks()` before `join_priors()`. |
| `read_animl_output()` | R/read_image.R | Complete | Ingest Animl CSV export (MegaDetector + SpeciesNet); map confidence + taxonomy to match object. Accepts long format (default) or wide format via `n_candidates`. Configurable column names via `file_col`, `species_col`, `score_col`. `observation_id` = image filename stem. `min_confidence` and `top_n` filters. |
| `read_inaturalist_cv_output()` | R/read_image.R | Complete | Ingest saved iNaturalist CV API JSON response files (one JSON per image). `score_type` = `"combined_score"` (default) or `"score"`. Returns `observation_id`, `score`, `species`, `genus`, `common_name`, `taxon_rank`, `source_file`. `min_confidence`, `top_n` filters. Requires `jsonlite`. |
| `read_wildlife_insights_output()` | R/read_image.R | Complete | Ingest SpeciesNet / Wildlife Insights batch predictions JSON (one JSON may cover many images). `label_col = "label"`, `score_col = "score"` (configurable for older formats). Returns `observation_id`, `score`, `species`, `genus`, `category`, `source_file`. `min_confidence`, `top_n` filters. Requires `jsonlite`. |
| `read_birdnet_output()` | R/read_acoustic.R | Complete | Ingest BirdNET-Analyzer CSV (detections × species × confidence); map to match object. Accepts file vector or directory path. `observation_id = "{file_stem}_{start_s}-{end_s}"`. `min_confidence` and `top_n` filters. |

### Site table and spatial grouping (Sessions 134, 134b)

| Function | File | Status | Description |
|---|---|---|---|
| `build_site_table()` | R/build_site_table.R | Complete | Unifies per-observation site info (`observation_id`, `lat`, `lon`, `observed_on`) across all three match-object pathways into one long-format table. Image pathway (`score_image_inat()` output): extracted directly from embedded `lat`/`lng`/`observed_on`. DNA/BLAST and acoustic pathways: neither carries site info in the match object itself, so `site_df` must be supplied externally; may have more than one row per `observation_id` -- this is the correct shape for a sequence ASV genuinely detected at several real sample sites in one sequencing run (see Session 134 note). **Session 134b:** also populates `spatial_group_id` (default = the row's own `observation_id`) and `spatial_group_N` (default = `1L`) on every row from the moment the table is built, so every site table has valid, non-missing values before any grouping step runs -- `group_observations_by_bbox()`/`assign_spatial_group()` update these in place. |
| `group_observations_by_bbox()` | R/group_observations_by_bbox.R | Complete | **Session 134b, moved here from TaxaFetch and reworked** (see that session's note below for the full design rationale). Interactive: loops `TaxaTools::define_search_polygon()` (re-centred each time on still-default observations, guaranteed to fully enclose them) to collect one or more group polygons, then an end-of-loop review step (list drawn groups by member count; re-open one by number to reshape via `init_polygon`; `"delete <n>"` to remove one, releasing its members back to default; Enter to finalize). Updates `spatial_group_id`/`spatial_group_N` **in place** on a `build_site_table()`-shaped input -- only touches observations still at their default single-observation state; anything already grouped (prior call, or `assign_spatial_group()`) is left untouched regardless of geometry. Overlap rule: **last-drawn-wins** with a `warning()` naming every ambiguous `observation_id`. Internal helpers `.bbox_center_radius()`, `.assign_spatial_groups_from_polygons()`, and `.review_drawn_groups()`'s non-interactive/zero-polygon paths are pure and unit-tested without a live gadget session. |
| `assign_spatial_group()` | R/assign_spatial_group.R | Complete | **Session 134b.** Manual `spatial_group_id` setter for a named set of observations -- for a study where grouping is already known from metadata, or to hand-correct a few observations after `group_observations_by_bbox()`. Validates every named `observation_id` exists; **collision guard**: stops if the target `spatial_group_id` is already used by an observation *not* named in the call (would otherwise silently expand an unrelated group's membership) -- include that observation explicitly to merge groups instead. Recomputes `spatial_group_N` in sync. |

### Standardization (original)

| Function | File | Status | Description |
|---|---|---|---|
| `standardize_match_data()` | R/standardize_match_data.R | Written | Rename columns, derive `taxon_name`, validate structure |
| `filter_redundant_hypotheses()` | R/standardize_match_data.R | Written | Drop higher-rank rows superseded by finer-rank rows within the same lineage and sample |
| `add_lowest_consistent_rank()` | R/taxonomy_consistency.R | Written | Per-observation: find finest rank with a single unambiguous value across all candidate rows. `majority_threshold` param (numeric in (0,1]) switches to majority mode — consistent when top value reaches threshold. Majority mode adds `rank_majority_value`, `rank_majority_fraction`, `is_rank_outlier` columns. `na_as_inconsistent` controls NA handling. Auto-detects `rank_system` from `TaxaTools::extended_ranks`. |
| `convert_taxonomy_backbone()` | R/convert_taxonomy_backbone.R | Written | Remap rank columns (order/family/genus/species) from source backbone to target backbone (e.g. NCBI→GBIF). Vectorized: `match()`-based index into verified table — ~100× faster than row-by-row loop for large data frames. Per-column fallback: ranks the target omits are kept unchanged. Adds `taxonomy_backbone` and `taxonomy_collision` diagnostic columns; sets `backbone_cols` R attribute. NOTE: generic utility — move to TaxaTools after manuscript review. |

### Internal helpers

| Function | File | Description |
|---|---|---|
| `.resolve_taxonomy()` | R/blast.R | NCBI taxid to full lineage (kingdom-species) via rentrez + xml2 |
| `.resolve_locations_by_acc()` | R/blast.R | **Session 135.** Accession → `lat`/`lon`/`country` via full GBSeq XML record (`db="nucleotide", rettype="gb", retmode="xml"`) — the record type `.resolve_taxonomy()`/`.resolve_taxonomy_by_acc()` never touch. Accessions passed directly as `id`, no search/summary round trip. |
| `.parse_lat_lon()` | R/blast.R | **Session 135.** Parses INSDC `lat_lon` qualifier strings (`"36.789 N 121.947 W"`) into signed decimal `c(lat=, lon=)`. Deliberately duplicated from TaxaLikely's identical helper (`R/fetch.R`) rather than shared — matches this ecosystem's existing pre-manuscript stance on small NCBI-fetcher overlap (see `project_blast_ncbi_fetcher_todo` memory / TaxaLikely's Session 115 note). |
| `.parse_taxonomy_xml()` | R/blast.R | Parse NCBI taxonomy XML response |
| `.blast_remote()` | R/blast.R | Remote NCBI BLAST URL API with batching, rate limiting, RID polling |
| `.blast_local()` | R/blast.R | Local BLAST via rBLAST wrapper |
| `.filter_blast_hits()` | R/blast.R | Score window algorithm: min_score + query coverage + subject length + score_range + max_hits |
| `.parse_blast_xml()` | R/blast.R | Parse BLAST XML output into standardized hit data frame |
| `.resolve_taxonomy_from_accessions()` | R/blast.R | Accession-to-taxonomy bridge when taxids unavailable (XML format) |
| *(removed — Session 57)* | R/sequence_input.R, R/blast.R | `.barcode_length_defaults` and `.resolve_barcode_lengths_local()` moved to TaxaTools; now `TaxaTools::resolve_barcode_lengths()` |
| `.parse_semicolon_headers()` | R/sequence_input.R | Parse FASTA headers: accession;kingdom;...;species |

---

## Workflow Scripts

| File | Purpose |
|---|---|
| `inst/workflow_standardize.R` | Original: load match data, standardize, filter redundant |
| `inst/workflow_fastq_to_match.R` | FASTQ-to-match pipeline: DADA2 output, filter, BLAST, standardize |
| `inst/workflows/score_image_workflow.R` | Layer-1 (Session 124): live `score_image_inat()` call on bundled real camera-trap photos (`inst/extdata/example_images/camera_trap_photos/`) → `fill_higher_ranks()` → checkpoint for TaxaLikely. **Expanded Session 129**: 6 photos/5 species → 52 photos/8 species, organized into per-species subfolders (`recursive = TRUE`; `folder_1` drives ground truth via `FOLDER_TO_SPECIES`, since filenames are camera-generated sequence numbers, not species names). Added a `TARGET_ICONIC_TAXA = "Mammalia"` post-scoring filter — iNaturalist returns off-scope candidates (two plants, one bird, confirmed on this exact photo set) that a mammal-only study can never actually assign to; filtering before `unreferenced_candidates()`/`assign_scores()` lets real candidates absorb that probability mass instead. `top_n` raised 5→8 as a safety margin. |
| `inst/workflows/score_acoustic_workflow.R` | Layer-1 (Session 124): `read_birdnet_output()` on real BirdNET-Analyzer CSVs (produced by `sources/birdnet_csv_export.py`, a companion Python script outside this package) → `create_taxon_names()` + `fill_higher_ranks()` → checkpoint for TaxaLikely |
| `inst/workflows/blast_sequences_workflow.R` | Layer-1 (Session 126): live remote `blast_sequences()` call on 5 real PtConception 12S MiFish sequences (same accessions as Session 115's field test, fetched live by accession from NCBI) → `standardize_match_data()` (with `coverage_col = "query_coverage"`) → checkpoint for TaxaLikely's sequence Layer-1 script |

---

## Score Window Algorithm (blast_sequences)

Rather than a flat top-N cutoff, `blast_sequences()` filters per query:
1. Remove hits below `min_score` (default 70%)
2. Remove hits with query coverage below `min_query_coverage` (default 80%)
3. Remove hits with subject length outside barcode range (via `barcode_term`)
4. Per query: keep all hits within `score_range` of the top hit (default 2%)
5. Apply `max_hits` safety cap per query (default 20)

A clear top match may return only 1-3 hits. An ambiguous query retains all
plausible candidates.

---

## Barcode Length Defaults

**Session 57 (Prompt 16):** Local copies of `.barcode_length_defaults` and
`.resolve_barcode_lengths_local()` removed from `R/sequence_input.R` and `R/blast.R`.
Now uses `TaxaTools::barcode_length_defaults` and `TaxaTools::resolve_barcode_lengths()`
(single source of truth). See TaxaTools CLAUDE.md for the full barcode length table.

---

## `filter_redundant_hypotheses()`

**Purpose:** When a match pipeline returns both species-level and genus-level hits for the
same sample, the genus-level row is redundant — it adds no information that the species
row doesn't already provide, and it inflates the taxon list sent to TaxaLikely / TaxaAssign.
This function removes such redundant higher-rank rows while retaining genus/family rows
for lineages that have NO species-level match.

**Critical design point — redundancy is lineage-local, not global:**
A genus-level row for *Gobius* is redundant only if a *Gobius* species row also appears
for the same `observation_id`. It is NOT redundant merely because some other species-level row
(e.g., *Acanthogobius flavimanus*) exists in the same sample. Dropping all genus rows
whenever any species match exists would silently discard real alternative hypotheses.

**Algorithm:**

1. Convert `taxon_name_rank` to a numeric rank score using the supplied `rank_system`
   vector (e.g., `c("kingdom","phylum","class","order","family","genus","species")`).
   Position in vector = score; species = highest, kingdom = lowest.

2. For each `observation_id × row`, determine whether any other row in the same `observation_id`
   satisfies BOTH:
   - Its rank score is strictly higher (finer rank), AND
   - It shares the same values in ALL taxonomy columns that correspond to ranks coarser
     than or equal to the current row's rank.
   (This checks "is this row an ancestor of any finer-rank row?")

3. Drop rows for which step 2 is TRUE.

**No score column required** — the only ordering information needed is the rank ordering
vector and the taxonomy columns (kingdom → species). The DNA/image/acoustic match score
is irrelevant to this filter.

**Input requirements:**
- `match_df` with `observation_id`, `taxon_name_rank`, and the full set of taxonomy columns
  named in `rank_system` (populated down to the matched rank; finer ranks are NA).
- `rank_system`: character vector, coarsest first (e.g., `kpcofgs`).
  Rows with `taxon_name_rank` not found in `rank_system` are retained unchanged with a
  warning.

**Signature (proposed):**
```r
filter_redundant_hypotheses <- function(match_df,
                                         rank_system = c("kingdom","phylum","class",
                                                        "order","family","genus","species"))
```

**Example:** sample S1 has rows for *Gobius paganellus* (species), *Gobius* sp. (genus),
and *Acanthogobius* sp. (genus). The *Gobius* genus row is dropped (superseded by
*G. paganellus*). The *Acanthogobius* genus row is retained (no species match for that
lineage).

**Where to call it:** Inside `standardize_match_data()` as an optional step, or as a
standalone exported function called explicitly. Recommend standalone so callers can
inspect before and after. Should run AFTER `create_taxon_names()` so `taxon_name_rank`
is already populated.

**Note for implementation:** The prototype `f_filter_redundant_higher_hypotheses()` in
`TaxaAssign/inst/TaxaAssign_llm_workflow.R` (Session 36) uses a score-column approach
that conflates rank ordering with match quality and applies a global (not lineage-local)
filter. The rewrite described here supersedes it. The `f_score_ordinal_col()` helper in
the same workflow file has been removed (Session 39); rank scoring is now handled inline
inside `filter_redundant_hypotheses()` via `match()`.

---

## Key Design Notes

- Column renaming uses `TaxaTools::rename_cols()` with a source-specific `col_map`
- Taxonomic name derivation uses `TaxaTools::create_taxon_names()`
- Output must conform exactly to the match object spec above before passing to TaxaLikely
- `TestId` (marker type) and `Accession` (reference accession) are retained but not
  renamed and play no role in the likelihood model

---

## Session Notes

**Session 135 (2026-07-05): blast_sequences(resolve_location=) — GenBank location extraction for BLAST hits**

Companion to TaxaLikely's same-session fetch-side work — together they close two of
the three location-metadata gaps flagged in `ecosystem_docs/
TODO_validation_benchmark.md`'s "Sourcing location data from online reference
records" section (BOLD's equivalent remains a separate, unchecked TBD; wiring either
into a real `build_site_table()` `site_df` call is left for benchmark-harness time).
Explicitly scoped to this plumbing only — the leave-one-out benchmark harness itself
stays gated behind the user's 2026-07-04 directive.

Confirmed directly: `.resolve_taxonomy()` and `.resolve_taxonomy_by_acc()` only ever
reach the NCBI **taxonomy** database (lineage), never `db="nucleotide"`, so a BLAST
hit's collection coordinates were never in scope regardless of `resolve_taxonomy`.
Added `.parse_lat_lon()` (INSDC `lat_lon` qualifier parser, identical to TaxaLikely's
own — deliberately duplicated rather than shared, matching this ecosystem's existing
pre-manuscript stance) and `.resolve_locations_by_acc()` (fetches full GBSeq XML by
accession directly, no search→summary round trip). `blast_sequences(resolve_location =
FALSE)` — new opt-in trailing param; when `TRUE`, resolves unique hit accessions and
left-joins `lat`/`lon`/`country` onto the output (version-suffix-stripped join key on
both sides, defensive since `GBSeq_primary-accession` is already version-free but
BLAST's `sacc` isn't guaranteed to be).

New tests in `test-blast.R`: `.parse_lat_lon()` (5 cases, same coverage as TaxaLikely's
mirror), `.resolve_locations_by_acc()` empty-input typing, `resolve_location` input
validation. `devtools::document()` + `devtools::test()` (406 expectations, 0 failures,
0 warnings) + `devtools::check()` (0 errors, 0 warnings, 0 notes) all clean.

**Session 134b (2026-07-04): group_observations_by_bbox() moved here and reworked; assign_spatial_group() added**

Branch `single-observation-pipeline`. Follow-up to Session 134 below and to TaxaFetch's
Session 134 (`group_observations_by_bbox()` originally landed there). After the user
reviewed that implementation and raised design questions before committing (recorded in
`ecosystem_docs/REENTRY_PROMPT_session134b_grouping_implemented.md`), three decisions
were confirmed and implemented this session:

- **Package placement:** `group_observations_by_bbox()` moved from TaxaFetch to TaxaMatch.
  It operates on `build_site_table()`'s output and decides `spatial_group_id` membership --
  a spatial-grouping concern that belongs next to the site table, not a fetch concern.
  `TaxaTools::define_search_polygon()` (also moved this session, from TaxaFetch) is the
  shared gadget both this function and TaxaFetch's search-area use now call.
- **`build_site_table()` reframed as the source of truth for `spatial_group_id`/
  `spatial_group_N` defaults**, not `group_observations_by_bbox()`. Every site table now
  gets `spatial_group_id` (default = the row's own `observation_id`) and `spatial_group_N`
  (default = `1L`) from the moment it's built -- solving the original worry that a
  downstream function could assume these columns exist on a site table that never went
  through grouping. `group_observations_by_bbox()` **updates these columns in place**
  for whichever observations get captured by a drawn box; this simplified the "leftover"
  handling considerably -- an observation outside every drawn box just keeps its existing
  default, no separate singleton-numbering logic needed (the old
  `"spatial_group_<n>"`-for-everyone convention from TaxaFetch's Session 134 is
  superseded by this simpler default-to-`observation_id` shape; multi-member groups still
  use `"spatial_group_1"`, `"spatial_group_2"`, ... in draw order).
- **Manual assignment mechanism:** `assign_spatial_group()` added, a validating helper
  rather than "just document that the column is editable" -- the user wanted the
  collision guard (see Function Inventory entry above) rather than relying on callers to
  get it right by hand.

Also implemented, per the reentry prompt's "settled after further review" items:
- **Last-drawn-wins overlap rule** (reversing the old first-drawn-wins): when an
  observation falls inside more than one drawn polygon, the most recently drawn one's
  group wins, with a `warning()` naming every ambiguous `observation_id`. Required
  restructuring `.assign_spatial_groups_from_polygons()` to check every still-default
  point against every polygon (not just points still "remaining" as boxes are drawn),
  since two drawn boxes can geometrically overlap even though the interactive loop's own
  view-narrowing heuristic only shows "not yet captured" points at each step.
- **End-of-loop review/edit/delete step** (`.review_drawn_groups()`): after the user
  cancels the draw loop, a numbered summary of drawn groups with member counts; entering
  a number reopens that group's polygon via `TaxaTools::define_search_polygon(
  init_polygon = ...)` for reshaping (new gadget param, see TaxaTools/CLAUDE.md);
  `"delete <n>"` removes a group, releasing its members back to the default pool;
  Enter/`"done"` finalizes. No-op (returns polygons unchanged) when zero polygons were
  drawn or the session is non-interactive -- same testing boundary as the gadget itself.
- **Default starting polygon full-enclosure guarantee confirmed, not just assumed:**
  `.bbox_center_radius()`'s `radius_deg = max(half-ranges) * pad` (pad = 1.2) was already
  correct but only implicitly so; added an explicit test
  (`.bbox_center_radius()`'s "fully enclose every input point" case) and documented it as
  a guaranteed property in the roxygen, per the reentry prompt's request to confirm this
  before relying on it.

**Live-testing hazard found and mitigated (same session, after a real user report) --
initial hypothesis corrected below:** the first live run produced a fully unchanged
result -- a box was drawn around a real cluster and "Done" was clicked, but the returned
table showed no grouping applied at all, and no second gadget opened. Two mitigations
were added while investigating: (1) `message()` progress feedback throughout the draw
loop (box N captured M of N remaining; how many boxes recorded after Cancel; how many
after review) so a live run's console transcript makes the actual sequence of events
visible instead of opaque; (2) an explicit roxygen `@details` warning about running
`group_observations_by_bbox()` as one isolated command, since its review step reads
console input via `readline()` and RStudio can queue a following line as pending console
input if both are submitted together. Both are harmless and worth keeping, but **neither
was the actual root cause** -- an initial "RStudio queues the next line as readline()'s
answer" hypothesis was floated and written up here, but the real bug (found via
extended debugging, including Claude's Chrome browser-automation tools reproducing the
exact gadget in a real browser) was that **`TaxaTools::define_search_polygon()`'s Done
button never returned a value at all** when opened via RStudio's `dialogViewer()` --
confirmed reproducible even in a bare, no-loop, no-`readline()` standalone call. See
`TaxaTools/CLAUDE.md`'s Session 134b note for the full root-cause record and fix
(`define_search_polygon()` now defaults to `shiny::paneViewer(minHeight = 500)` instead
of `dialogViewer()` -- `browserViewer()` was the first fix and also confirmed working,
but the user pointed out `paneViewer()` matches this ecosystem's other mapping gadgets
and should be preferred for a consistent interaction style, which was then verified
directly against this exact gadget too). With that fixed, `group_observations_by_bbox()`
needed no code changes of its own -- it inherits the new default automatically, so it
now opens each box-drawing step in RStudio's Viewer pane, same as before the bug, just
via a different (working) viewer call. The `readline()`-queuing hazard documented above
is still real and still worth avoiding, just wasn't what happened here.

**Not done this session** (still open, see the reentry prompt's remaining items): the
search-area-vs-spatial-group reconciliation (`points` param support for group-coloring
was added to `define_search_polygon()`, but the actual per-group search-area drawing
workflow is deferred to the fetch-scope-wiring session), fetch-scope branching itself
(pooled fetch for multi-member groups vs. taxonomic escalation for singletons), the
Reads-table relocation, and the TaxaAssign `(observation_id, site)` schema question.

16 new/rewritten tests in `test-group_observations_by_bbox.R` (fully offline; the old
15-test TaxaFetch version was rewritten for the new default-to-`observation_id` behavior
and last-drawn-wins logic, not just moved verbatim), plus 10 new tests in
`test-assign_spatial_group.R` and 2 new tests in `test-build_site_table.R` for the new
default columns. `sf` added to `DESCRIPTION` Imports. `devtools::document()` +
`devtools::test()` (390 expectations, 0 failures) + `devtools::check()` (0 errors, 0
warnings, 0 notes) all clean.

**Session 134 (2026-07-03): build_site_table() -- unified long-format site table**

Branch `single-observation-pipeline`. Closes (partially) the site-table contract gap
flagged in `ecosystem_docs/REENTRY_PROMPT_session134_single_observation_pipeline.md`
(also `~/.claude/projects/-Users-lafferty/memory/project_site_table_contract_gap.md`):
per-observation `lat`/`lon` is inconsistently present across the three match-object
pathways. Confirmed directly this session (not assumed): `read_birdnet_output()`'s
output carries **zero** site metadata -- only detection-window start/end times and the
source recording filename, nothing GPS-like at all. So acoustic (like DNA/BLAST) needs
site info supplied externally; only the image pathway (`score_image_inat()`) has it
embedded.

`build_site_table(match_df, site_df = NULL, id_col = "observation_id")` added
(`R/build_site_table.R`): when `match_df` carries embedded `lat`/`lng` (image pathway),
extracts and renames to the canonical `lat`/`lon`/`observed_on` shape directly, ignoring
(with a warning) any `site_df` supplied alongside. Otherwise requires `site_df`
(`observation_id`/`lat`/`lon`, optional `observed_on`) and joins it in, explicitly
allowing more than one `site_df` row per `observation_id` -- this is the correct,
intended shape for the ASV multi-site case flagged in the reentry prompt (a sequence
ASV genuinely detected at several real sites within one sequencing run produces multiple
`(observation_id, site)` rows sharing one likelihood, not a single row with one site).
14 new tests (`test-build_site_table.R`), fully offline. `devtools::test()`: 342
expectations, 0 failures. `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Not done this session** (left for the dedicated follow-up the reentry prompt already
flagged): relocating the Reads-table (ASV x sample matrix, each sample column carrying
an associated place + time) wide-to-long parsing logic from `TaxaFlag`'s
`inst/contaminant_workflow.R` pivot step into a proper TaxaMatch function that feeds
`build_site_table()`'s `site_df` argument directly for the sequence pathway -- confirmed
this session that no such reusable function exists yet anywhere in the ecosystem, only
an ad hoc `pivot_longer()` in that one workflow script, which doesn't yet parse
per-sample place/time out of the sample-label convention. `TaxaAssign`'s downstream
`(observation_id, site)` schema question (whether `join_priors()`/`compute_posterior()`/
`posterior_consensus()` need to key on the pair rather than `observation_id` alone) is
also still open, unaffected by this session's work.

**Session 132 (2026-07-03): non-portable filenames fixed (rename)**

Closed out the "known issue for next session" flagged at the end of Session 129's
note below. Renamed the `ground squirrel` folder → `ground_squirrel` and all 39
`" copy.JPG"` files → `"_copy.JPG"` under
`inst/extdata/example_images/camera_trap_photos/` via `git mv` (underscore
convention, matching `camera_trap_photos/` itself from Session 124). Updated the
`FOLDER_TO_SPECIES` key in `score_image_workflow.R` to `"ground_squirrel"` to
match. `devtools::check()`: 0 errors, 0 warnings, 0 notes — "checking for portable
file names" now OK. Live-verified by re-running `score_image_workflow.R`'s Steps
1-2 (real iNaturalist CV call, all 52 photos): 0 NA `true_species` values across
294 rows, `ground_squirrel`'s photos all correctly resolve to `Otospermophilus
beecheyi`, and top-1 accuracy (82%, 42/51) matches the prior session's pattern —
no regression from the rename. `devtools::install()` re-shipped the renamed data
to the canonical library (`/Library/Frameworks/R.framework/Versions/4.5-arm64/
Resources/library`) — note `Rscript -e` does not source `~/.Rprofile` the way
RStudio does, so a plain `Rscript`-driven `devtools::install()` can silently
target the wrong `.libPaths()[1]` (this session hit a stale `~/Library/R/4.0/
library` on the first attempt); `devtools::install()`'s existing-install
detection recovered by updating the already-installed copy in place, but calling
`.libPaths()` explicitly first is safer than relying on that.

**Session 129 (2026-07-03): score_image_workflow.R expanded to 8 species/52 photos; taxonomic-scope filter added**

Expanded from the original 6-photo/5-species diversity-only set (Session 124) to get
enough replicate photos per species to move past a small-n result on whether
`TaxaLikely::correct_training_bias()` should be enabled by default for the image
pathway — see `TaxaLikely/CLAUDE.md`'s Session 129 note for the calibration finding this
made possible (short answer: `tau ≈ 0`, correction should not be applied here).

- 3 new species added, all real photos of the user's own: Raccoon (*Procyon lotor*,
  Procyonidae), California Ground Squirrel (*Otospermophilus beecheyi*, Sciuridae),
  Virginia Opossum (*Didelphis virginiana*, Didelphidae) — 7 families total now.
- Photos reorganized from a flat file list into per-species subfolders (folder name =
  common name). `score_image_inat()` already supported `recursive = TRUE` and its own
  `folder_1` path-metadata column — used directly rather than hand-rolling file discovery
  or a per-filename ground-truth lookup, which would no longer have worked once filenames
  became camera-generated sequence numbers instead of descriptive names.
- **Real off-scope candidates found and filtered:** running the expanded set surfaced
  that iNaturalist's CV model returns candidates from any iconic taxon, not just mammals
  — *Baccharis pilularis* ("coyote brush", a plant) and *Acacia longifolia* both appeared
  for coyote.JPG, and a screech owl (*Megascops kennicottii* — the same taxon originally
  flagged as a `correct_training_bias()` flip in Session 128) appeared for rabbit.JPG.
  Added `TARGET_ICONIC_TAXA = "Mammalia"`, filtered right after scoring and before
  `unreferenced_candidates()`/`assign_scores()` ever see the candidates — this changes
  the actual likelihood math (removes competing probability mass), not just a post-hoc
  annotation. `top_n` raised 5→8 as a safety margin since filtering can remove some of
  each photo's candidate slate; a guard warns (does not silently drop) if any photo loses
  every candidate to the filter.

**Not done — known issue for next session:** the newly added photo filenames contain
spaces (`"01150531 copy.JPG"`) and the `"ground squirrel"` folder name does too, both
triggering `R CMD check`'s non-portable-filenames WARNING — the exact same issue class
already fixed once in this file's history (Session 124's `"camera trap photos"` →
`"camera_trap_photos"` rename), now recurring. Needs a rename across ~30 files plus a
matching key update to `FOLDER_TO_SPECIES` in `score_image_workflow.R`; not done this
session since it touches many tracked files. **Fixed in Session 132 (see above).**

**Session 126 (2026-07-01): Layer-1 workflow script for sequence/BLAST data type**

`inst/workflows/blast_sequences_workflow.R` added — the third and last Layer-1 data-type
script for TaxaMatch (image and acoustic done Session 124). Reproduces Session 115's
already-field-tested `inst/test_blast_remote.R` field test in the Layer-1 workflow-script
convention (`DEBUG_MODE`, explicit checkpoints, Output block) rather than introducing a
new example dataset: 5 real 12S MiFish sequences from the user's own PtConception eDNA
study, fetched live from NCBI by accession (OQ846539/OQ846195/OQ846544/OQ846550/OQ846725).
Live-tested, 0 errors: 5/5 (100%) top BLAST hits correct at ≥98% identity, matching Session
115's result exactly.

One addition beyond the original field test script: `standardize_match_data()` is now
called with `coverage_col = "query_coverage"`, renaming BLAST's own alignment-quality
metric to the canonical `coverage` column so TaxaLikely's `evaluate_likelihoods(
min_coverage = ...)` can consume it directly with no extra join — the original Session 115
script didn't carry this column through.

This is the first of a two-package mini-chain; it stops at the canonical match object
(`taxamatch_blast_match_obj` — 18 rows, 5 queries, 12 unique taxa across the 3-batch score
window). Consumer: TaxaLikely's sequence Layer-1 script (`build_sequence_matrix()` →
`train_likelihood_model()` → `evaluate_likelihoods()`) — see
`ecosystem_docs/REENTRY_PROMPT_session124_image_acoustic_workflows.md`, Stage 2, item 2.

**Session 124 (2026-07-01): Layer-1 workflow scripts for image and acoustic data types**

Item 4 of `ecosystem_docs/REENTRY_PROMPT_session123_layer1_workflows.md` — image/
acoustic was the recommended starting point (structurally simpler than sequence/BLAST,
no DECIPHER/reference-fetch step). Both new scripts are 100% real, live-tested, no
synthetic data:

- `score_image_workflow.R`: live `score_image_inat()` calls against real Bushnell
  trail-camera photos of 5 mammal species across 4 families (Bobcat, Coyote, Brush
  Rabbit, Western Spotted Skunk, Striped Skunk ×2; Central California coastal scrub,
  34.41 N / -119.86 W). Deliberately a DIVERSITY OF TAXA rather than many replicate
  photos of one species or a single confusable pair — consistent with how the
  BLAST/sequence field test (Session 115) demonstrates pipeline mechanics across a
  handful of real queries, not a CV-accuracy calibration study. 5/6 (83%) top-1 correct
  once the real site lat/lng was supplied (2 of 6 flipped from wrong to correct vs. no
  location — `combined_score` blends vision confidence with local occurrence
  frequency). The one miss (coyote.JPG) is a genuine name/geo-prior collision: top
  candidate was *Baccharis pilularis* ("coyote brush"), a locally abundant plant, not a
  taxonomic near-miss.
- `score_acoustic_workflow.R`: ingests real BirdNET-Analyzer CSV output (produced by
  `sources/birdnet_csv_export.py`, a companion Python script — not part of this R
  package — that downloads real Xeno-canto recordings and runs the actual BirdNET model
  via `birdnetlib`) for three confusable Calidris sandpipers. 37/42 (88%) detection
  windows correct; the misses are genuine acoustic confusion (background noise,
  Least Sandpiper mistaken for Western/Semipalmated), not bugs.

**Earlier iteration used bird photos that were replaced.** The first version of
`score_image_workflow.R` used Semipalmated/Western Sandpiper photos from the user's
manuscript folder (10/10, 100% — see superseded design notes below) — replaced after
the user pointed out those were screenshots sourced from eBird/Macaulay-Library-linked
checklists, not photos they had rights to redistribute in this public package. Also
discovered mid-session: `TaxaMatch/inst/extdata/` already contained untracked copies of
those same bird photos (Google Drive multi-parent-folder linking, not something this
session created) — left in place rather than deleted via `rm`, since deleting a
multi-parented Drive file through the desktop sync client can trash the object
everywhere it appears, including the user's original manuscript folder. The user needs
to unlink that folder-location manually via Drive's UI before those files are safe to
remove from the local filesystem.

**Bugs/gaps found by actually running these scripts (not caught by reading code):**
- `unreferenced_candidates()` needs >= 2 populated rank columns; both
  `score_image_inat()` and `read_birdnet_output()` output only `genus` (no `family`,
  no separate `species` column) — fixed in both scripts via
  `TaxaTools::fill_higher_ranks()` + `species <- taxon_name` (full binomial;
  convention confirmed from `fill_higher_ranks()`'s own `@examples`, which does the
  same rename for a sibling function).
- `read_birdnet_output()`'s output has no `taxon_name`/`taxon_name_rank` at all (only
  `species`/`genus`) — same cross-script contract gap as TaxaFetch's Bug #12 from the
  five-package chain; fixed via `TaxaTools::create_taxon_names()`.
- `assign_scores(score_type = "probability")` errors/warns when scores exceed 1 —
  correct for BirdNET's already-bounded 0-1 confidence, but iNat's `combined_score` is
  UNBOUNDED (observed values up to ~3000 on an easy photo) and needs
  `score_type = "similarity_softmax"` instead. Confirmed both score types
  ratio-normalize by the winning candidate's own score (`sc / max_sc` /
  `sc_softmax / max_ss`) — the winner's `score_likelihood` is therefore always exactly
  1.0 by construction; the meaningful comparison across observations is which taxon
  won, not the likelihood magnitude.
- Xeno-canto's v2 API (`https://xeno-canto.org/api/2/recordings`, used by the user's
  original `birdnet_calidris_selftest.py`) now 404s — fully removed, not just an auth
  change. v3 (`https://xeno-canto.org/api/3/recordings`) requires a key AND
  tag-based query syntax (`gen:X sp:Y type:call`, not free-text `query=X Y type:call`).
  **This also affects production code**: `TaxaLikely::.xc_recording_count()`
  (`R/coverage.R`) still calls the dead v2 endpoint — `audit_acoustic_coverage(
  xc_recordings = TRUE)` currently returns `NA` for every species silently (checks
  `resp_status != 200`, no warning). Not fixed this session (out of scope for the
  image/acoustic Layer-1 workflow task; flagged for the user to decide whether to fix).
- Xeno-canto now requires per-application API keys, not personal ones (confirmed from
  xeno-canto.org/explore/api) — the user registered/confirmed a key specifically for
  this workflow rather than reusing a personal one already in `~/.Renviron`.
- `INAT_API_TOKEN` is a short-lived JWT; this session's stored token had already expired
  (~1 week old) — a 401 means regenerate the token, not a code bug.
- Non-portable file names/paths: bundling real example photos under
  `inst/extdata/example_images/` triggered an R CMD check WARNING for directory names
  containing spaces (`"camera trap photos"`) — renamed to `camera_trap_photos`
  (underscore) to fix; 0 warnings after.

Sessions 27–82 archived in ecosystem_docs/session_notes/TaxaMatch_sessions.md.

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaMatch-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools), WERC
  review integration.

**Session 86 (2026-05-23)**
- No code changes. `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at
  TaxaID/ root). Disclaimer section removed from `README.md`.

**Session 87 (2026-05-26)**
- `read_birdnet_output()` implemented in `R/read_acoustic.R` (was Planned since Session 55).
  Reads BirdNET-Analyzer CSV output (one file per recording). Accepts file vector or directory.
  `observation_id = "{file_stem}_{start_s}-{end_s}"`. `score` = Confidence (0-1). `genus` derived
  from first word of Scientific name. `min_confidence` and `top_n` filters. `source_file` column
  for ground-truth join back to Xeno-canto reference metadata.
  Internal helper `.parse_birdnet_file()` validates required BirdNET columns.
- 9 offline tests in `tests/testthat/test-read_acoustic.R` (synthetic `tempfile()` + `write.csv()`
  BirdNET data — no real recordings needed).
- `devtools::check()`: 0 errors, 0 notes (2 pre-existing vignette warnings).

**Session 88 (2026-05-26)**
- Bug fix: `.parse_birdnet_file()` crashed with `"arguments imply differing number of rows: 1, 0"`
  when a BirdNET CSV contained only a header row and no detections (e.g., BirdNET found nothing
  above the confidence threshold in a short or quiet recording). Root cause: `source_file = basename(f)`
  has length 1 but all other columns (`start_vals`, `end_vals`, etc.) are `numeric(0)` / `character(0)`.
  Fix: added early return for `nrow(df) == 0L` that produces a correctly typed 0-row data frame
  and emits an informational message naming the empty file.
- 2 new tests in `test-read_acoustic.R` (total now 11): empty CSV returns 0-row data frame with
  correct columns; mix of empty + non-empty files returns only rows from non-empty file.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 93 (2026-05-27)**
- `read_inaturalist_cv_output()` added to `R/read_image.R`. Reads per-image JSON files saved from the
  iNaturalist computer vision API. `score_type = "combined_score"` (default) or `"score"`. Returns
  `observation_id`, `score`, `species`, `genus`, `common_name`, `taxon_rank`, `source_file`. Accepts
  directory of JSON files or a file vector. `min_confidence` and `top_n` filters. 8 offline tests.
- `read_wildlife_insights_output()` added to `R/read_image.R`. Reads SpeciesNet / Wildlife Insights
  batch predictions JSON (top-level `"predictions"` dict keyed by image filename). `label_col = "label"`,
  `score_col = "score"` configurable. Returns `observation_id`, `score`, `species`, `genus`, `category`,
  `source_file`. `min_confidence`, `top_n` filters. 8 offline tests.
- `jsonlite` added to DESCRIPTION Imports (required by both new reader functions; `requireNamespace`
  guard allows graceful error if not installed).
- README "Other Image Classifiers" section updated: dedicated reader functions shown with example code;
  classifier comparison table updated.
- `devtools::check()`: 0 errors, 0 warnings, 1 note (pre-existing top-level files).

**Session 119 (2026-06-24)**
- `score_image_inat()` added to `R/score_image_inat.R`. Submits image(s) directly to the
  iNaturalist CV API (`POST https://api.inaturalist.org/v1/computervision/score_image`) and
  returns a canonical match object. Accepts a single file path, a character vector of paths,
  or a directory (all JPEG/PNG files non-recursively). `observation_id` = filename stem.
- Per-image EXIF extraction via `exifr` (Suggests): reads `GPSLatitude`, `GPSLongitude`,
  `GPSLatitudeRef`, `GPSLongitudeRef`, `DateTimeOriginal`/`CreateDate` when `lat`/`lng`/
  `observed_on` are NULL. User-supplied scalar args override EXIF and apply to all images.
- Path folder columns (`folder_1`, `folder_2`, ...): directory levels between the input base
  path and each image file are output as separate columns, enabling study design metadata
  (site/date/treatment folders) to flow downstream.
- Output is already in canonical match object format: `observation_id`, `taxon_name`,
  `taxon_name_rank`, `score_original` (= `combined_score`). Supplemental columns:
  `genus`, `common_name`, `iconic_taxon_name`, `taxon_id`, `n_observations` (from
  `taxon$observations_count` in the CV response — no extra API call needed),
  `vision_score`, `combined_score`, `freq_score`, `geo_prior_weight` (= combined/vision),
  `lat`, `lng`, `observed_on`.
- Downstream note: run `convert_taxonomy_backbone()` then `fill_higher_ranks()` before
  `join_priors()` — documented in `@details`. `family` column not populated (not in CV response).
- `httr`, `dplyr`, `tibble` added to DESCRIPTION Imports. `exifr` added to Suggests.
- Internal helpers: `.resolve_image_files()`, `.path_folder_components()`,
  `.extract_exif_info()`, `.parse_inat_cv_response()`.
- `devtools::check()`: 0 errors, 0 notes, 1 pre-existing warning (TaxaLikely cross-references).

**Session 115 (2026-06-22)**
- Bug fix: `.blast_submit()` used `!!!params` (rlang splice) in `httr2::req_body_form()` call.
  `rlang` is not in TaxaMatch Imports; without it `!!!params` evaluates as `!(!(!params))` →
  error on a list. Remote BLAST would always fail at submission. Fixed to
  `do.call(httr2::req_body_form, c(list(httr2::request(base_url)), params))`.
- `blast_sequences()` field-tested on 5 PtConception MiFish sequences (OQ84xxxx series,
  168-170 bp). All 5/5 top hits returned at 100% to correct species; score window, taxonomy
  resolution, and `standardize_match_data()` all confirmed working end-to-end. Runtime ~18s
  for 1 batch of 5 sequences.
  Test script: `inst/test_blast_remote.R`.
- `workflow_fastq_to_match.R`: `library(dada2)` commented out (optional; only needed for
  Step 0). `infer_exclude_predicted()` call added as Step 3b (Session 114 addition).
- Shared NCBI fetcher design decision: no `.ncbi_fetch_records()` abstraction pre-manuscript.
  The three NCBI use-cases differ fundamentally (blast_sequences is reverse: accession → taxid
  → lineage; fetch_reference_sequences and audit_barcode_coverage are forward: taxon → NCBI).
  Only shared piece is taxid→lineage resolution (~30 lines each). Consolidate into TaxaTools
  after manuscript review.
- `devtools::check()`: 0 errors, 0 notes, 1 pre-existing warning (cross-references to removed
  TaxaLikely functions from Session 97).

**Session 113 (2026-06-19)**
- `add_lowest_consistent_rank()` added to `R/taxonomy_consistency.R`. Strict mode
  (default): rank consistent when every non-blank candidate value is identical.
  New `majority_threshold` param (numeric in (0,1]): switches to majority mode where
  rank is consistent if top non-blank value accounts for ≥ threshold of non-blank
  candidates. Majority mode adds three columns: `rank_majority_value`,
  `rank_majority_fraction`, `is_rank_outlier`. `is_rank_outlier = TRUE` for rows whose
  value at `lowest_consistent_rank` differs from the majority value; NA/blank rows are
  FALSE (missing data, not a contradiction). Interaction filter pattern:
  `!(is_rank_outlier & lowest_consistent_rank %in% coarse_ranks)` — removes rows only
  when both conditions are true simultaneously. Note: `NA %in% c(...)` returns FALSE, so
  NA `lowest_consistent_rank` observations silently pass such filters.
  8 new majority-mode tests in `test-taxonomy_consistency.R`; 73/73 tests passing.
- `convert_taxonomy_backbone()` rewritten as vectorized implementation. Replaced
  O(N×K) row-by-row loop with `match()`-based index into `verified` table +
  `ifelse()` per column. Logical matrix for collision detection; `apply()` only on
  changed-row subset. `strsplit` called once per unique name (not once per rank × name).
  NA taxon_name rows now get NA backbone/collision columns (not `source_label`).
  Fixed `path[[idx]]` out-of-bounds when GNVerifier returns path/ranks vectors of
  unequal length: guard `|| idx > length(path)` added.
  `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 110 (2026-06-16)**
- `convert_taxonomy_backbone()` added to `R/convert_taxonomy_backbone.R`.
  Remaps rank columns (default: order, family, genus, species) from a source backbone
  to a target backbone via `verify_taxon_names()`. Per-column fallback: ranks the target
  backbone omits are left unchanged (no NA introduction). Adds `taxonomy_backbone` and
  `taxonomy_collision` diagnostic columns; sets `backbone_cols` R attribute + prints
  summary message. `update_taxon_name = TRUE` (default) cleans authority strings from
  accepted names and saves original to `taxon_name_original`. `verify_fn` parameter
  allows offline testing via dependency injection.
  `taxonomy_collision` values: `"consistent"`, `"backbone_N[col1,col2]"` (target applied,
  changed columns listed), `"backbone_N"` or `"original"` (not found in target).
  32 offline tests in `tests/testthat/test-convert_taxonomy_backbone.R`.
  NOTE: generic utility — should move to TaxaTools after manuscript review.
- `TaxaMatch-package.R` Standardization section updated.
- `devtools::check()`: 0 errors, 0 notes, 1 pre-existing warning (removed TaxaLikely
  cross-reference links from Session 97).
