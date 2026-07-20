# =============================================================================
# TaxaID eDNA Analysis Workflow — Generic Template
# Pipeline: TaxaMatch -> TaxaTools -> TaxaFetch -> TaxaHabitat -> TaxaExpect ->
#           TaxaLikely -> TaxaAssign -> TaxaFlag
#
# =============================================================================
# 0.  CONFIGURATION  (edit this section only)
# =============================================================================

library(dplyr)
library(tidyr)
library(TaxaTools)
library(TaxaFetch)
library(TaxaHabitat)
library(TaxaExpect)
library(TaxaMatch)
library(TaxaLikely)
library(TaxaAssign)
library(TaxaFlag)
library(ggplot2)
#added..
library(DECIPHER)
library(rentrez)

#packages to install:
# --- Output directory (for saving large files)--------------------------------------------------------
OUT_DIR <- getwd() #or set.
OUT_PREFIX <- "TaxaID_test"
# Helper: save an RDS with a standard name (useful for outputs from functions that use an api)
.save <- function(obj, tag) {
  path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_", tag, ".rds"))
  saveRDS(obj, path)
  message(sprintf("  Saved %s_%s.rds", OUT_PREFIX, tag))
  invisible(path)
}

# Helper: load a cached RDS if present, otherwise evaluate `expr` and save it.
# Unlike a hand-written if/file.exists()/else block, the assignment always
# happens on the caller's LHS (never inside a branch) -- there is no way for
# a cache hit to leave the target object unset. `expr` is lazily evaluated,
# so on a cache hit the (possibly slow/API-calling) code in `expr` never runs.
# Usage: raw_gbif <- .cached("raw_gbif", download_gbif_occurrences(...))
.cached <- function(tag, expr) {
  path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_", tag, ".rds"))
  if (file.exists(path)) {
    message(sprintf("  Loading cached %s from disk (delete %s to force re-fetch).", tag, path))
    return(readRDS(path))
  }
  obj <- expr
  .save(obj, tag)
  obj
}

# --- Taxonomic backbone IDs --------------------------------------------------
fgs <- c("family", "genus", "species") #define a taxonomic rank system.
MATCH_BACKBONE_ID <- 4L   # NCBI — backbone used by BLAST reference database
PRIOR_BACKBONE_ID <- 11L  # GBIF — backbone used for occurrences and expansion_taxonomy

# --- Study area --------------------------------------------------------------
STUDY_LAT    <- 34.4                     # Decimal degrees
STUDY_LON    <- -120.4
STUDY_RADIUS <- .5                        # Degrees (~330 km per degree) 2-3 is a large area
YEAR_RANGE   <- "1995,2025"
GBIF_LIMIT   <- 10000L

# --- Single-observation escalation settings (Section 2.5/3) -------------------
SINGLETON_RADIUS_DEG  <- 0.05             # Local, non-interactive fetch radius for a
                                          # single-observation spatial group -- broadened
                                          # taxonomically (below), never spatially/pooled.
ESCALATION_MAX_LEVELS <- 2L               # genus -> family -> order

# --- Sample-to-site metadata (Section 2.5) ------------------------------------
# The same kind of lookup table already used to identify blanks (blank_ids,
# Section 2), generalized to carry real per-sample site coordinates instead
# of (or alongside) blank status -- see
# ecosystem_docs/REENTRY_PROMPT_session137_observation_pipeline_wiring.md,
# Phase 4. One row per Reads_Table sample column (event_id); control_1 has no
# real site (it's a blank, excluded via control_samples before the join, same
# as Section 2's contaminant check) but is listed here anyway for
# completeness -- any columns genuinely never sampled at a real place should
# simply be omitted, not given placeholder coordinates.
SAMPLE_SITE_METADATA <- tibble(
  event_id    = c("sample_1", "sample_2", "control_1"),
  lat         = c(34.40, 34.47, NA),
  lon         = c(-120.41, -120.36, NA),
  observed_on = c("2026-03-14", "2026-03-14", "2026-03-14")
)
# One ASV in Reads_Table (OQ846725) has real (non-blank) reads in BOTH
# sample_1 AND sample_2 -- a genuine multi-site ASV. build_site_table()
# defaults both of its site rows to the SAME spatial_group_id (its own
# observation_id), so this ASV has 2 site rows under one spatial_group_id --
# the stored spatial_group_N column counts SITE ROWS, not distinct
# observations, and is unreliable for this reason (see Section 3's own note).
# Session 137 first surfaced this as a live bug (Phase 6 test run); Session
# 138 fixed Sections 3 and 5 to branch on the number of DISTINCT
# observation_id values in a group rather than the row count, so this case
# is now handled correctly: per-site (not pooled, not interactively-boxed)
# occurrence fetch and per-site (not averaged-centroid) prior generation,
# feeding combine_multisite_priors() in Section 7 with genuinely different
# per-site priors.

# --- TaxaExpect model settings -----------------------------------------------
MORAN_K      <- 5L                       # Spatial basis vectors
SD_THRESHOLD <- 0.20                     # Random effect SD threshold for model screening
SITE_HABITAT <- "Marine"                 # Target site habitat

# --- TaxaLikely reference/coverage settings -----------------------------------
BARCODE_TERM <- "12S"                    # Marker term for audit_barcode_coverage();
                                          # matches this template's tiny MiFish-style test sequences

# --- Review context (Step 9) -------------------------------------------------
REVIEW_CONTEXT <- list(
  geography = "Pt. Conception, CA Pacific Ocean",
  habitat   = "coastal marine"
)

#tiny FASTA ASV table
ASV_TABLE_test <-
  tibble(
  asv_id=c("OQ846544","OQ846550","OQ846725"),
    sequence = c("CACCGCGGTTATACGAGAGGCCCTAGTTGATAACTACCGGCGTAAAGAGTGGTTACGGAAAAATATTTAATAAAGCCGAACACCCCCTCAGCCGTCATACGCACCTGGGGGCACGAAGATCTACTACGAAAGCAGCTTTAATTATACCTGAACCCACGACAGCTACGACA",
                 "CACCGCGGTTATACGAGAGGCCCAAGTTGACAGATACCGGCGTAAAACGTGGCTAAACTGCCCCCTCCCAACTAAAGCCAAACACCTTCAAAGCTGTGATACGCAAACGAAGGCAGGAAGTCCTACCACGAAAGTGGCTTTATCCATTTGAGCCCACGAAAGCTAGAAAA",
                 "gccataagtg aaaacttgac ttagttaaag ctaagagggc cggtaaaact cgtgccagcc accgcggtta tacgagcgac ccaagttgag agacaacggc gtaaagagtg gataagatac taataaacta aagccgaacg ccctcaagac tgttatacgt"
))

#tiny FASTA reads table
Reads_Table <-
  tibble(observation_id=c("OQ846544","OQ846550","OQ846725"),sample_1=c(0,20,5),sample_2=c(0,0,20),control_1=c(20,0,1))

# SEQUENCE DATA
#Three entry points: (i) FASTQ, (ii) FASTA or (iii) BLAST-annotated_ASV_tables.
# i) Process FASTQ files through a denoising pipeline to infer amplicon
#  sequence variants (ASVs) exported in FASTA format (not part of this workflow).
# ii) Annotate FASTA files with taxonomic candidates for each ASV.
BLAST_annotated_ASV_table_full <-
  TaxaMatch::blast_sequences(
  ASV_TABLE_test,
  max_hits          = 5L,
  email              = "lafferty@ucsb.edu",
  ncbi_api_key       = Sys.getenv("ENTREZ_KEY") %||% NULL,
)
.save(BLAST_annotated_ASV_table_full, "BLAST")

BLAST_annotated_ASV_table <-
  BLAST_annotated_ASV_table_full|>
dplyr::select(
    any_of(c("observation_id", "score", "family", "genus", "species"))
  )

# B) Standardize column names for analysis
#
annotated_table <- #standardize the match table columns and clean names.
  TaxaMatch::standardize_match_data(
  data               = BLAST_annotated_ASV_table,
  observation_id_col = "observation_id", #existing ID name
  score_col          = "score", #existing score name
  rank_system        =  fgs# #existing vector of taxonomic rank column names e.g., ("Kingdom,Phylum..Species)
) |>
  TaxaTools::create_taxon_names(rank_system=fgs) |> #create a new "taxon_name" column that indicates the lowest ranked name
  mutate(
    taxon_name=TaxaTools::clean_taxon_names(taxon_name)) #|> #clean taxon_name from common problems.
    #select(!all_of(fgs))

#adding a taxon not present in GBIF to show how it can be handled
conflict_row<-tibble(
  observation_id="OQ876544",
  score_original=100,
  family="Cottidae",
  genus="XXX",
  species="XXX vvv",
  taxon_name="XXX vvv"
)

annotated_table<-bind_rows(conflict_row,annotated_table)


#C) verify names on a new taxonomic backbone (GBIF)
#base new names on the cleaned taxon_name.
taxonomic_names <-
  annotated_table |>
  pull(taxon_name) |>
  unique() |>
  verify_taxon_names(backbone_id = 11)

#a table to convert new backbone to columns.
taxonomic_columns <- as.data.frame(setNames(
  lapply(fgs, function(rk) {
    unname(mapply(
      TaxaTools::parse_classification_path,
      taxonomic_names$classification_path,
      taxonomic_names$classification_ranks,
      MoreArgs = list(target_rank = rk)
    ))
  }),
  fgs
))


#use the table to append the annotated_table with clean GBIF taxonomy.
annotated_table_GBIF<-cbind(taxonomic_names,taxonomic_columns)|>
  dplyr::select(matched_name,all_of(fgs))|>
  dplyr::rename(taxon_name=matched_name) |>
  left_join(annotated_table)

#switching to GBIF can drop some taxa that do not have records in the GBIF backbone.
#These will return NA and can be patched with their NCBI name.
annotated_table_GBIF_patched <-
bind_rows(
annotated_table_GBIF[!is.na(annotated_table_GBIF$taxon_name),]|>mutate(backbone="GBIF-NCBI"),
annotated_table[is.na(annotated_table_GBIF$taxon_name),]|>mutate(backbone="NCBI")
)

#detect synonyms introduced through the backbone merge.
#If present, fix them.
TaxaTools::find_taxonomy_conflicts(annotated_table_GBIF_patched,
                        rank_system=c("family","genus"))

# =============================================================================
# 2.  CONTAMINANT DETECTION (TaxaFlag)
# =============================================================================
# Mostly commonly for sequence data, but similar steps might be used for images or sounds.
# For instance MegaDetector helps identify blanks images. The steps below are for sequences.
# If you have Read files: per-sample read counts in

# wide format (columns = event_ids). flag_contaminant() compares read proportions across blank vs. field samples.
# All ESVs are retained; lab_contaminant_risk is joined in Steps 6 and 9.
# READ_META: columns present in read files that are NOT event_id columns.
# Adjust this list to match your lab's read-count file format.

blank_ids <- c("control_1") #any columns that identify a blank.
reads_long <- Reads_Table |> #convert the standard wide reads table into long format
  pivot_longer(cols = -any_of("observation_id"), names_to = "event_id", values_to = "n_reads")

# Resolve blank event_ids. Adjust matching logic for your blank naming scheme:
#   exact match: event_id %in% BLANKS_RUN1
#   prefix match: sub("\\..*$", "", event_id) %in% BLANKS_RUN2

contaminant_flags <- TaxaFlag::flag_contaminant(
  df               = reads_long,
  event_col        = "event_id",
  taxon_col        = "observation_id",
  reads_col        = "n_reads",
  control_samples  = blank_ids, #unquoted
  contaminant_type = "lab_contaminant"
)
contaminant_ids <- contaminant_flags%>%filter(lab_contaminant_risk=="high") |>
  pull(names(contaminant_flags)[1])

decontaminated_table <-
  annotated_table_GBIF_patched |>
  filter( #remove ASVs identified as contaminants.
    !observation_id%in%contaminant_ids
  )
# Captured before the rename below so Section 2.5 can relabel site_df's
# observation_id to match decontaminated_table's easier-to-track IDs.
.original_to_asv_id <- stats::setNames(
  paste0("ASV_", match(unique(decontaminated_table$observation_id), unique(decontaminated_table$observation_id))),
  unique(decontaminated_table$observation_id)
)
decontaminated_table <- decontaminated_table |>
  mutate( #change observation_ids to something easier to track.
    observation_id = paste0("ASV_", match(observation_id, unique(observation_id)))
  )

# =============================================================================
# 2.5  SPATIAL GROUPING (TaxaMatch)
# =============================================================================
# Groups observations sharing a bounding box for one pooled, community-level
# occurrence/reference fetch (Sections 3/6) and prior (Section 5); observations
# that stay singletons after grouping fall through to the taxonomic-escalation
# path instead (broadened genus -> family -> order via
# TaxaTools::escalate_taxonomic_rank(), never pooled with unrelated
# observations). See ecosystem_docs/REENTRY_PROMPT_session137_observation_
# pipeline_wiring.md for the full design.
#
# TaxaMatch::join_event_site_metadata() (Phase 4) attaches SAMPLE_SITE_METADATA
# (above) to the real Reads_Table long-format detections already built for
# Section 2's contaminant check (reads_long, blank_ids) -- the same "sample
# column -> attribute lookup table" pattern already used to identify blanks,
# generalized to site coordinates. observation_id is relabeled via
# .original_to_asv_id (captured in Section 2) so it matches
# decontaminated_table's renamed IDs. sample_1 and sample_2 are genuinely
# different real coordinates here, so this template's bundled test data now
# exercises actual multi-site grouping, not just the wiring pattern on one
# hardcoded point.
detections <- reads_long |>
  filter(n_reads > 0) |>
  mutate(observation_id = .original_to_asv_id[observation_id])

site_df <- TaxaMatch::join_event_site_metadata(
  detections      = detections,
  site_metadata   = SAMPLE_SITE_METADATA,
  event_col       = "event_id",
  id_col          = "observation_id",
  control_samples = blank_ids
)

# Fallback for any decontaminated_table observation with no Reads_Table row at
# all (e.g. this template's own conflict_row demo taxon, added in Section 1
# purely to show GBIF taxonomy-conflict handling -- it was never a real
# sequenced sample). Never silently drop an observation from spatial grouping;
# give it the single hardcoded STUDY_LAT/STUDY_LON instead, same as this
# section's behavior before real site metadata existed.
.no_site <- setdiff(unique(decontaminated_table$observation_id), unique(site_df$observation_id))
if (length(.no_site) > 0L) {
  message(sprintf(
    "  %d observation(s) have no Reads_Table sample row at all -- falling back to STUDY_LAT/STUDY_LON: %s",
    length(.no_site), paste(.no_site, collapse = ", ")
  ))
  site_df <- dplyr::bind_rows(site_df, tibble(
    observation_id = .no_site, lat = STUDY_LAT, lon = STUDY_LON, observed_on = NA_character_
  ))
}

site_table <- TaxaMatch::build_site_table(
  decontaminated_table, site_df = site_df, id_col = "observation_id"
)

if (interactive()) {
  site_table <- TaxaMatch::group_observations_by_bbox(site_table)
} else {
  message("  Non-interactive session -- skipping group_observations_by_bbox(); ",
          "every observation stays at its default single-observation spatial group.")
}

.save(site_table, "site_table")

# =============================================================================
# 3.  OCCURRENCE DATA (TaxaFetch)
# =============================================================================
# Find occurrences for the matched taxa and their relatives.
#
# Two passes, per the taxon-centric fetch-efficiency design (Session 139;
# see ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md for
# the full discussion this implements). Grouping the fetch loop by
# observation/site (the pre-Session-139 design) meant two overlapping site
# boxes wanting the same taxon issued two separately-issued GBIF queries,
# risking the same record being counted twice downstream -- confirmed to
# actually happen with this template's own bundled OQ846725/ASV_2 case.
#
#   Pass 1 -- define every spatial_group_id's search geometry, no fetching
#     yet: an interactively-drawn polygon for multi-member groups (>= 2
#     DISTINCT observation_id values -- the existing clustered design), or
#     one automatic small bbox per site row (SINGLETON_RADIUS_DEG) for
#     single-observation groups (exactly 1 distinct observation_id, whether
#     it has 1 or N site rows -- e.g. a genuine multi-site observation like
#     OQ846725/ASV_2). Interleaving box-definition with fetching (the old
#     design) made it impossible to union a taxon's geometry across groups
#     that hadn't been drawn yet.
#   Pass 2 -- build one taxon_key -> geometry map spanning BOTH branches
#     (family keys for multi-member groups, genus keys for single-observation
#     groups) and fetch once per taxon key via
#     TaxaFetch::fetch_occurrences_by_taxon(), which unions each taxon's own
#     geometry (dissolving the overlapping-query duplicate-record risk at
#     the source) and combines different taxa sharing identical geometry
#     into one call. Single-observation genus-level candidates that come
#     back with zero matching records are escalated
#     (TaxaTools::escalate_taxonomic_rank(), genus -> family -> order) and
#     refetched, up to ESCALATION_MAX_LEVELS additional rounds -- escalation
#     is decided per starting genus, not per site: sites sharing a candidate
#     genus already share the same escalation path, and a nonzero result
#     anywhere in that genus's unioned search area means real local data
#     exists for it (no need for per-site spatial attribution to decide
#     whether THIS site individually would have escalated on its own).
#     Multi-member (family-level) rows never escalate, matching the
#     pre-Session-139 behavior for that branch.
# =============================================================================

group_ids <- unique(site_table$spatial_group_id)

# --- Pass 1: define geometry only, no fetching -----------------------------
group_geometry <- vector("list", length(group_ids))

for (.g in seq_along(group_ids)) {

  group_id    <- group_ids[.g]
  group_sites <- site_table[site_table$spatial_group_id == group_id, , drop = FALSE]
  n_distinct_obs <- dplyr::n_distinct(group_sites$observation_id)

  # dplyr::n_distinct(group_sites$observation_id), NOT nrow(group_sites): a
  # genuine multi-site single observation (one observation_id, >1 site row)
  # must NOT be routed into the multi-member pooled/interactive-bbox branch
  # below just because it has multiple site ROWS (Session 138 fix).
  if (n_distinct_obs >= 2L) {

    message(sprintf(
      "Section 3, Pass 1: group %d/%d ('%s') -- %d distinct observation(s), %d site row(s) -- draw a search area.",
      .g, length(group_ids), group_id, n_distinct_obs, nrow(group_sites)
    ))

    bbox <- TaxaTools::define_search_polygon(
      lat        = mean(range(group_sites$lat)),
      lon        = mean(range(group_sites$lon)),
      radius_deg = STUDY_RADIUS,
      points     = data.frame(lat = group_sites$lat, lng = group_sites$lon),
      title      = sprintf("Define Search Area for %s (%d observation(s))", group_id, n_distinct_obs)
    )

    # define_search_polygon() returns NULL if its gadget is cancelled/closed
    # without Done. A pooled multi-member fetch needs a real, deliberately-
    # drawn search area -- there's no sensible automatic fallback the way
    # the singleton path has SINGLETON_RADIUS_DEG -- so stop with a clear,
    # actionable message immediately (Pass 1, before any fetching starts)
    # rather than passing NULL through to a later fetch call.
    if (is.null(bbox)) {
      stop(sprintf(
        paste0(
          "Section 3, Pass 1: define_search_polygon() was cancelled for multi-member group '%s' ",
          "(%d observation(s): %s). A pooled fetch needs a drawn search area -- re-run ",
          "this section and click Done after drawing a box."
        ),
        group_id, n_distinct_obs, paste(unique(group_sites$observation_id), collapse = ", ")
      ), call. = FALSE)
    }

    group_geometry[[.g]] <- list(type = "multi_member", group_id = group_id,
                                  geometry = bbox, sites = group_sites)

  } else {

    message(sprintf(
      "Section 3, Pass 1: group %d/%d ('%s') -- 1 distinct observation, %d site row(s) -- automatic local bbox(es).",
      .g, length(group_ids), group_id, nrow(group_sites)
    ))

    site_bbox <- vapply(seq_len(nrow(group_sites)), function(.s) {
      TaxaFetch::make_bbox_wkt(
        lat = group_sites$lat[.s], lon = group_sites$lon[.s],
        radius_deg = SINGLETON_RADIUS_DEG
      )
    }, character(1L))

    group_geometry[[.g]] <- list(type = "singleton", group_id = group_id,
                                  geometry = site_bbox, sites = group_sites)
  }
}

# --- Pass 2: build the combined taxon_key -> geometry map, fetch once ------

# Multi-member groups: family-level candidates, resolved once, never
# escalated -- one row per (family, group's own drawn polygon).
multi_member_map <- dplyr::bind_rows(lapply(group_geometry, function(gg) {
  if (gg$type != "multi_member") return(NULL)
  group_members <- decontaminated_table[
    decontaminated_table$observation_id %in% gg$sites$observation_id, , drop = FALSE
  ]
  families  <- unique(group_members$family)
  taxa_keys <- TaxaFetch::get_keys_from_context(tibble(family = families))
  valid     <- taxa_keys[!is.na(taxa_keys$usageKey), , drop = FALSE]
  if (nrow(valid) == 0L) return(NULL)
  tibble(
    taxon_key  = valid$usageKey,
    geometry   = gg$geometry,
    rank_name  = "family",
    taxon_name = valid$family
  )
}))

# Single-observation groups: one row per (site, candidate genus) -- not yet
# resolved to a usageKey, since taxon_name/rank_name change across
# escalation rounds (resolved fresh each round by .resolve_round_keys()).
singleton_rows <- dplyr::bind_rows(lapply(group_geometry, function(gg) {
  if (gg$type != "singleton") return(NULL)
  group_members <- decontaminated_table[
    decontaminated_table$observation_id %in% gg$sites$observation_id, , drop = FALSE
  ]
  # nzchar() guard, not just na.omit(): a low-confidence match can leave genus
  # as an empty string rather than NA, and an empty string sent onward as a
  # "taxon name" resolves to nonsense (confirmed on real PtConception data,
  # where it reached fetch_ncbi_reference_sequences() below and crashed --
  # see the empirical PtConceptionWorkflow_12S/18S_2 fix this mirrors).
  candidate_genera <- unique(stats::na.omit(group_members$genus))
  candidate_genera <- candidate_genera[nzchar(candidate_genera)]
  if (length(candidate_genera) == 0L) return(NULL)
  tidyr::crossing(site_idx = seq_along(gg$geometry), taxon_name = candidate_genera) |>
    dplyr::mutate(geometry = gg$geometry[site_idx], rank_name = "genus") |>
    dplyr::select(-site_idx)
}))

# Resolves each unique (taxon_name, rank_name) pair in `df` to a usageKey
# (one get_keys_from_context() call per rank present, not per row -- sites
# sharing a candidate genus/family share one lookup) and drops rows whose
# name never resolves to a key at all (mirrors the pre-Session-139 escalation
# ladder's own behavior: an unresolvable name still counts as "found
# nothing" and is eligible to escalate further).
.resolve_round_keys <- function(df) {
  by_rank <- split(df, df$rank_name)
  resolved <- lapply(by_rank, function(d) {
    key_df  <- stats::setNames(data.frame(unique(d$taxon_name), stringsAsFactors = FALSE), d$rank_name[1L])
    key_row <- TaxaFetch::get_keys_from_context(key_df)
    lookup  <- stats::setNames(key_row$usageKey, key_row[[d$rank_name[1L]]])
    d$taxon_key <- lookup[d$taxon_name]
    d
  })
  dplyr::bind_rows(resolved)
}

# Rank-agnostic zero-hit check: does `occ` contain any row whose `rank_name`
# text column matches `taxon_name` (case-insensitive)? Matching on the
# taxonomic text column (always present, every rank) rather than a *Key
# column avoids relying on GBIF usage-key columns that aren't all present in
# the standard schema (e.g. no orderKey).
.found_taxa <- function(occ, rank_name, taxon_names) {
  if (nrow(occ) == 0L || !rank_name %in% names(occ)) return(character(0))
  present <- unique(occ[[rank_name]][!is.na(occ[[rank_name]])])
  taxon_names[tolower(trimws(taxon_names)) %in% tolower(trimws(present))]
}

singleton_round0 <- if (nrow(singleton_rows) > 0L) {
  .resolve_round_keys(singleton_rows)
} else {
  singleton_rows
}

round0_map <- dplyr::bind_rows(multi_member_map, singleton_round0) |>
  dplyr::filter(!is.na(taxon_key))

message(sprintf(
  "Section 3, Pass 2: round 0 -- %d distinct taxon key(s) (%d family, %d genus).",
  dplyr::n_distinct(round0_map$taxon_key),
  dplyr::n_distinct(round0_map$taxon_key[round0_map$rank_name == "family"]),
  dplyr::n_distinct(round0_map$taxon_key[round0_map$rank_name == "genus"])
))

occ_round0 <- .cached("occ_round0", TaxaFetch::fetch_occurrences_by_taxon(
  taxon_geometry_map = round0_map[, c("taxon_key", "geometry")],
  year_range = YEAR_RANGE,
  limit      = GBIF_LIMIT,
  exclude_absent = TRUE,
  basis_keep = c("HUMAN_OBSERVATION", "MACHINE_OBSERVATION")
))

occ_rounds <- list(occ_round0)

# Only single-observation (genus-level) candidates ever escalate -- a
# multi-member group's family-level fetch never did, before or after
# Session 139.
found0   <- .found_taxa(occ_round0, "genus", unique(singleton_round0$taxon_name))
pending  <- singleton_rows[!singleton_rows$taxon_name %in% found0, , drop = FALSE]

for (.round in seq_len(ESCALATION_MAX_LEVELS)) {
  if (nrow(pending) == 0L) break

  # Keyed on (taxon_name, rank_name), not taxon_name alone -- a name could in
  # principle appear at two different ranks among still-pending rows (e.g. a
  # rare cross-rank homonym), and rank_name is always known/unambiguous here.
  zero_pairs <- unique(pending[, c("taxon_name", "rank_name")])
  escalated  <- dplyr::bind_rows(lapply(seq_len(nrow(zero_pairs)), function(i) {
    step <- TaxaTools::escalate_taxonomic_rank(
      zero_pairs$taxon_name[i], current_rank = zero_pairs$rank_name[i], verbose = FALSE
    )
    if (is.na(step$taxon_name)) return(NULL)
    tibble(
      taxon_name = zero_pairs$taxon_name[i], rank_name = zero_pairs$rank_name[i],
      new_name = step$taxon_name, new_rank = step$rank
    )
  }))

  if (is.null(escalated) || nrow(escalated) == 0L) {
    message("Section 3, Pass 2: no further escalation possible for any remaining candidate -- stopping.")
    break
  }

  pending <- pending |>
    dplyr::inner_join(escalated, by = c("taxon_name", "rank_name")) |>
    dplyr::mutate(taxon_name = new_name, rank_name = new_rank) |>
    dplyr::select(-new_name, -new_rank)

  round_map <- .resolve_round_keys(pending) |> dplyr::filter(!is.na(taxon_key))
  if (nrow(round_map) == 0L) break

  message(sprintf(
    "Section 3, Pass 2: escalation round %d/%d -- %d distinct taxon key(s).",
    .round, ESCALATION_MAX_LEVELS, dplyr::n_distinct(round_map$taxon_key)
  ))

  occ_this_round <- .cached(paste0("occ_round", .round), TaxaFetch::fetch_occurrences_by_taxon(
    taxon_geometry_map = round_map[, c("taxon_key", "geometry")],
    year_range = YEAR_RANGE,
    limit      = GBIF_LIMIT,
    exclude_absent = TRUE,
    basis_keep = c("HUMAN_OBSERVATION", "MACHINE_OBSERVATION")
  ))
  occ_rounds <- c(occ_rounds, list(occ_this_round))

  found_this_round <- unlist(lapply(unique(round_map$rank_name), function(r) {
    .found_taxa(occ_this_round, r, unique(round_map$taxon_name[round_map$rank_name == r]))
  }))
  pending <- pending[!pending$taxon_name %in% found_this_round, , drop = FALSE]
}

gbif_occurrences <- dplyr::bind_rows(occ_rounds) |>
  # coord uncertainty (intentionally retains NA )
  dplyr::filter(is.na(coordinateUncertaintyInMeters) | coordinateUncertaintyInMeters <= 3000)|>
 # decimal places (counts digits after the decimal point)
  dplyr::filter(nchar(sub(".*\\.", "", as.character(decimalLatitude))) >= 2)

.save(gbif_occurrences, "gbif_occurrences")
# Explicit checkpoint (not automatic) -- no file.exists()-gated auto-reload;
# you decide when to reuse this (e.g. to skip re-fetching from GBIF). Paste
# the line below yourself when you want it:
#   gbif_occurrences <- readRDS(file.path(OUT_DIR, paste0(OUT_PREFIX, "_gbif_occurrences.rds")))

#Add additional data (see TaxaFetch for various data fetching options.)
additional_occurrences<-
  tibble(species = c("Phanerodon furcatus"),
         genus = c("Phanerodon"),
         family = c("Embioticidae"),
         decimalLatitude = c(STUDY_LAT),
         decimalLongitude = c(STUDY_LON))

all_occurrences <-
  TaxaFetch::stack_occurrences(additional_occurrences,gbif_occurrences)|> #creates point_id
  TaxaTools::create_taxon_names(rank_system = fgs) |>
  filter(taxon_name_rank == "species") |>
  dplyr::select(any_of(c("point_id","decimalLatitude", "decimalLongitude",
                         "taxon_name", fgs)))

all_occurrences$taxon_name <- TaxaTools::clean_taxon_names(all_occurrences$taxon_name)

.save(all_occurrences, "all_occurrences")

# =============================================================================
# 4.  HABITAT ASSIGNMENT (TaxaHabitat)
# =============================================================================
# LLM assigns a habitat class to each taxon based on the supplied scheme.
# flag_habitat_inconsistencies() + review_spatial_flags() allows interactive
# review of spatially anomalous records before modelling.
#
# No spatial_group_id branching needed here: habitat is an LLM classification
# per TAXON, not per site, so it applies uniformly to the pooled occurrence
# data from every spatial group at once (Section 3's gbif_occurrences already
# combines all groups). Grouping only starts to matter again in Section 5,
# where priors are generated per group's own resolved site.

taxa_in_data <- unique(all_occurrences$taxon_name)

#edit, but fewer categories is better for modeling.
simple_scheme <- data.frame(
  l1_name = c("Marine", "Estuarine", "Freshwater", "Terrestrial"),
  stringsAsFactors = FALSE
)

prompt     <- TaxaHabitat::build_habitat_prompt(taxa_in_data, habitat_scheme = simple_scheme)
.llm_fn_   <- function(p, ...) call_anthropic_api(p, model = "claude-sonnet-4-6")
LLM_output <- prompt_api(prompt, llm_fn = .llm_fn_)

habitat_lookup <- TaxaHabitat::parse_hierarchical_habitat_response(
  LLM_output,
  taxon_list     = prompt$taxa,
  habitat_scheme = prompt
)
occurrences_with_habitat <- TaxaHabitat::assign_habitat_biological(
  data         = all_occurrences,
  habitats_df  = habitat_lookup,
  point_id_col = "point_id",
  threshold    = 0.5
)

n_assigned <- occurrences_with_habitat |>
  filter(!is.na(main_habitat)) |>
  distinct(decimalLatitude, decimalLongitude) |>
  nrow()

occurrences_flagged <- TaxaHabitat::flag_habitat_inconsistencies(occurrences_with_habitat)
system("afplay /System/Library/Sounds/Ping.aiff", wait = FALSE)  # Shiny app ready
.shiny_t0        <- proc.time()[["elapsed"]]
reviewed_spatial <- review_spatial_flags(occurrences_flagged)

occurrences_clean <- filter(reviewed_spatial, spatial_flag == "likely")
.save(occurrences_clean, "occurrences_clean")

# =============================================================================
# 5.  TAXAEXPECT — SPECIES DISTRIBUTION MODEL + PRIORS
# =============================================================================
#
# =============================================================================

n_covariates    <- 2L
grid_result     <- TaxaExpect::optimize_grid_size(observation_data = occurrences_with_habitat,
                                      n_covariates = n_covariates)
occurrences_gridded <- TaxaExpect::create_sites_from_grid(occurrences_with_habitat,
                                              grid_size = grid_result$best_grid)
model_data <- TaxaExpect::prepare_model_dataframe(occurrences_gridded)


# k must be < the number of distinct grid cells (compute_moran_basis() errors
# otherwise), and even a valid k can still fail on a sparse/poorly-connected
# grid ("no positive eigenvalues found") -- both observed running this exact
# function on small real data in TaxaExpect::generate_priors_workflow.R.
# MORAN_K is now a ceiling, not a fixed value; wrap in tryCatch() and treat a
# failure as "skip the Moran basis" rather than a hard stop -- the formula
# below is built to tolerate zero B columns for the same reason.
n_grid_cells <- dplyr::n_distinct(model_data$grid_id)
moran_k      <- min(MORAN_K, n_grid_cells - 1L)

basis <- if (moran_k >= 1L) {
  tryCatch(
    TaxaExpect::compute_moran_basis(grid_ids = unique(model_data$grid_id), k = moran_k),
    error = function(e) {
      message(sprintf("  compute_moran_basis() failed (%s) -- skipping Moran basis.",
                      conditionMessage(e)))
      NULL
    }
  )
} else NULL

if (!is.null(basis)) {
  model_data <- left_join(model_data, basis, by = "grid_id")
  message(sprintf("  Moran basis joined: %d MEM column(s) (k = %d, %d grid cell(s)).",
                  sum(grepl("^B[0-9]+$", names(basis))), moran_k, n_grid_cells))
} else {
  message(sprintf("  No Moran eigenvector basis available for %d grid cell(s) -- ",
                  n_grid_cells), "omitting spatial-autocorrelation terms below.")
}

# Moran terms built from whatever B columns actually exist (zero, one, or
# more) rather than hardcoded -- a hardcoded (0 + B1 | taxon_name) errors
# outright if basis computation above was skipped or returned fewer columns.
n_moran_cols <- sum(grepl("^B[0-9]+$", names(model_data)))
moran_terms  <- if (n_moran_cols > 0L) {
  sprintf("(0 + B%d | taxon_name)", seq_len(n_moran_cols))
} else character(0)

#scale the model formula to fit the complexity of the data (simplified here for example)
rhs_terms <- c(
  #"main_habitat",
  "(1 | taxon_name)",
  #"diag(main_habitat | taxon_name)",
  moran_terms,
  "(0 + lat_r_s | taxon_name)",
  "(0 + lon_r_s | taxon_name)",
  "(1 | taxon_name:grid_id)"
)
model_formula_full <- stats::as.formula(
  paste("cbind(n_species, n_other) ~", paste(rhs_terms, collapse = " + "))
)

model_fit <- TaxaExpect::screen_spatial_formula(
  data          = model_data,
  formula_full  = model_formula_full,
  sd_threshold  = SD_THRESHOLD,
  delta_aic_max = 2.0,
  verbose       = TRUE
)

# Generate priors once per spatial group (Section 2.5), not once globally.
# The regional community MODEL FIT above (model_fit) already pools ALL
# occurrence data across every group -- spatial grouping only changes WHICH
# site each group's own priors get generated for below. Each group's
# coordinates resolve to a real grid cell at the same grid_size the model was
# fit on; if that exact cell has no modelled data at SITE_HABITAT (a real,
# expected gap with sparse regional data), fall back to the busiest grid cell
# for that habitat -- the same heuristic this template used before per-group
# branching existed, now scoped as a documented fallback rather than the
# only option. Keep the global_floor row (main_habitat = NA) in
# priors_undetected so that join_priors() has a principled fallback for
# completely unmodelled species.
.resolve_group_grid_id <- function(lat, lon, grid_size, habitat, model_data) {
  candidate <- TaxaExpect::create_sites_from_grid(
    data.frame(lat = lat, lon = lon), grid_size = grid_size,
    lat_col = "lat", lon_col = "lon"
  )$grid_id
  has_data <- any(model_data$grid_id == candidate & model_data$main_habitat == habitat)
  if (has_data) return(candidate)
  message(sprintf(
    "  Spatial group's resolved grid cell (%s) has no modelled data at habitat '%s' -- ",
    candidate, habitat), "falling back to the busiest grid cell for that habitat.")
  model_data |>
    dplyr::filter(main_habitat == habitat) |>
    dplyr::count(grid_id) |>
    dplyr::slice_max(n, n = 1, with_ties = FALSE) |>
    dplyr::pull(grid_id)
}

priors_undetected <- TaxaExpect::generate_undetected_diversity(
  model_obj = model_fit,
  taxonomy  = occurrences_with_habitat  #
) |>
  # Singleton mirrors carry the grid_id of where each singleton was observed
  # (not the focal site) — grid_id filter drops all of them. Habitat filter only.
  filter(main_habitat == SITE_HABITAT | is.na(main_habitat))

# Prior-generation units, Session 138 fix: a multi-member cluster gets ONE
# representative centroid per group, as before -- a small drawn bounding box
# is assumed to resolve to one grid cell; a group spanning more than one grid
# cell (grid_size smaller than the box) is a known simplification here, not a
# rigorous per-member nearest-grid design. But a single-observation group
# (whether it has 1 or N site rows) now gets ONE UNIT PER SITE ROW, using
# that site's own real coordinates directly -- never averaged. Averaging a
# genuine multi-site observation's real sites into one centroid (the
# pre-Session-138 behavior) silently destroyed the very per-site distinction
# combine_multisite_priors() (Section 7) needs to combine.
site_table_aug <- site_table |>
  dplyr::group_by(spatial_group_id) |>
  dplyr::mutate(n_obs_in_group = dplyr::n_distinct(observation_id),
                .site_row      = dplyr::row_number()) |>
  dplyr::ungroup()

prior_units <- dplyr::bind_rows(
  site_table_aug |>
    dplyr::filter(n_obs_in_group >= 2L) |>
    dplyr::group_by(spatial_group_id) |>
    dplyr::summarise(lat = mean(lat), lon = mean(lon), .groups = "drop") |>
    dplyr::mutate(unit_id = spatial_group_id, observation_id = NA_character_,
                  .site_row = NA_integer_),
  site_table_aug |>
    dplyr::filter(n_obs_in_group == 1L) |>
    dplyr::mutate(unit_id = paste0(spatial_group_id, "__site", .site_row)) |>
    dplyr::select(unit_id, spatial_group_id, observation_id, .site_row, lat, lon)
)

taxaexpect_priors_by_group <- list()
group_grid_lookup          <- vector("list", nrow(prior_units))

for (.g in seq_len(nrow(prior_units))) {
  uid  <- prior_units$unit_id[.g]
  glat <- prior_units$lat[.g]
  glon <- prior_units$lon[.g]

  grid_id_g <- .resolve_group_grid_id(glat, glon, grid_result$best_grid, SITE_HABITAT, model_data)

  site_data_g <- model_data |>
    filter(grid_id == grid_id_g, main_habitat == SITE_HABITAT)

  taxaexpect_priors_by_group[[uid]] <- TaxaExpect::generate_full_priors(
    model_obj  = model_fit,
    new_sites  = site_data_g,
    undetected = priors_undetected
  ) |>
    dplyr::mutate(taxon_name_rank = "species")

  group_grid_lookup[[.g]] <- tibble(
    unit_id          = uid,
    spatial_group_id = prior_units$spatial_group_id[.g],
    observation_id   = prior_units$observation_id[.g],
    .site_row        = prior_units$.site_row[.g],
    grid_id          = grid_id_g,
    main_habitat     = SITE_HABITAT
  )
}

group_grid_lookup <- dplyr::bind_rows(group_grid_lookup)
taxaexpect_priors  <- dplyr::bind_rows(taxaexpect_priors_by_group) |> dplyr::distinct()

# site_for_join: one row per (observation_id, site) -- a genuine multi-site
# observation naturally produces MULTIPLE rows here (Session 138), matching
# join_priors()'s multi-site data-frame contract exactly, instead of one row
# per observation_id collapsed to an averaged centroid.
site_for_join <- dplyr::bind_rows(
  # Multi-member cluster members: join by spatial_group_id to that group's
  # single averaged-centroid prior (unchanged design).
  site_table_aug |>
    dplyr::filter(n_obs_in_group >= 2L) |>
    dplyr::select(observation_id, spatial_group_id) |>
    dplyr::left_join(
      group_grid_lookup |>
        dplyr::filter(is.na(observation_id)) |>
        dplyr::select(spatial_group_id, grid_id, main_habitat),
      by = "spatial_group_id"
    ) |>
    dplyr::select(observation_id, grid_id, main_habitat),
  # Single-observation groups (both single- and multi-site): join by
  # (spatial_group_id, .site_row) to their own site-specific prior.
  site_table_aug |>
    dplyr::filter(n_obs_in_group == 1L) |>
    dplyr::left_join(
      group_grid_lookup |>
        dplyr::filter(!is.na(observation_id)) |>
        dplyr::select(spatial_group_id, .site_row, grid_id, main_habitat),
      by = c("spatial_group_id", ".site_row")
    ) |>
    dplyr::select(observation_id, grid_id, main_habitat)
)

#Generate a map from which one can confirm that priors line up with observations. This is most useful
#when predictions are generated for a range of points rather than a focal point.
TaxaExpect::plot_theta_map_interactive(taxaexpect_priors, occurrences_with_habitat, tile = "OpenStreetMap")

#!!!!! STOPPED HERE 1 July -- continued below (Sections 6-8 added)
# =============================================================================
# 6.  LIKELIHOOD MODEL (TaxaLikely)
# =============================================================================
# Requires DECIPHER + Biostrings (Bioconductor):
#   BiocManager::install("DECIPHER")
#
# 6a builds a pairwise sequence matrix (cached after first run).
# 6a.5 detects and restores suppressed candidates (BLAST 100%-rule artefact).
# 6b trains the bivariate-normal likelihood model.
# 6c evaluates likelihoods for all queries.
# 6d audits reference database completeness (NCBI barcode coverage).

# match_obj is the standardized, contaminant-filtered, GBIF-backbone-patched
# ASV table from Section 2/1 -- the shape TaxaLikely's coverage/restoration
# functions expect (observation_id, score_original, taxon_name, family/genus/species).
match_obj <- decontaminated_table

# 6a. Build reference sequence database ---------------------------------------
# Session 139 rewrite: previously built by reusing whatever accessions BLAST
# itself happened to hit (BLAST_annotated_ASV_table_full$accession), with no
# control over reference sequence length or contamination status. Two real
# bugs this caused, found via a live Phase 6 run (see
# ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md for the
# full root-cause and the barcode-length design discussion):
#   1. GenBank mixes short, purpose-built barcode submissions with full
#      mitogenomes (~16.5kb) for the same species/gene. build_sequence_matrix()
#      silently drops anything outside its own length window (default
#      100-2000bp) *after* download -- in this template's real bundled data,
#      every within-species pair happened to come from a dropped mitogenome
#      duplicate, leaving ZERO same-species pairs and a hard training failure
#      ("No H1 pairs found").
#   2. acc_unique was pulled from BLAST_annotated_ASV_table_full -- the RAW,
#      pre-decontamination BLAST output -- so a flagged lab contaminant
#      (Salmo salar / OQ846544, excluded from decontaminated_table in Section
#      2) still ended up in the reference database and fed model training.
#
# fetch_ncbi_reference_sequences() fixes both at the source: it filters
# candidate sequences by length BEFORE downloading (via
# TaxaTools::resolve_barcode_lengths(BARCODE_TERM) -- "12S" defaults to
# 100-600bp), so mitogenomes are never fetched at all; and its `taxa` list is
# derived from match_obj (already contaminant-filtered), not raw BLAST output,
# so an excluded contaminant can never re-enter via the reference set.
#
# max_len widened to 1200bp (from the "12S" default's 600bp): this template's
# real data includes legitimate ~850-950bp full/partial 12S-gene-region
# reference submissions -- longer than a tight PCR-amplicon default, but nowhere
# near mitogenome length (16.5kb, >13x this ceiling). This is a judgment call,
# not a fixed rule -- revisit if a different marker/study shows different
# submission-length patterns.
candidate_genera <- match_obj |>
  # nzchar() guard, not just !is.na(): a low-confidence match can leave genus
  # as an empty string rather than NA; an empty string sent to
  # fetch_ncbi_reference_sequences() below as a "taxon name" crashes it
  # (confirmed on real PtConception data -- see the empirical
  # PtConceptionWorkflow_12S/18S_2 fix this mirrors).
  dplyr::filter(!is.na(genus) & nzchar(genus)) |>
  dplyr::distinct(genus) |>
  dplyr::pull(genus)

reference_df <- TaxaLikely::fetch_ncbi_reference_sequences(
  taxa            = candidate_genera,
  barcode_term    = BARCODE_TERM,
  rank_system     = c("family", "genus", "species"),
  max_len         = 1200L,
  max_per_species = 10L,
  ncbi_api_key    = Sys.getenv("ENTREZ_KEY") %||% NULL
)
message(sprintf("  %d reference sequence(s) fetched across %d genus/genera.",
                nrow(reference_df), length(candidate_genera)))
seq_matrix <- build_sequence_matrix(reference_df,
                                    rank_system = c("family", "genus", "species"))
.save(seq_matrix, "seq_matrix")
.save(reference_df, "reference_df")
# Explicit checkpoint (not automatic) -- no file.exists()-gated auto-reload;
# you decide when to reuse this (e.g. to skip re-fetching FASTA from NCBI).
# Paste both lines below yourself when you want it:
#   seq_matrix   <- readRDS(file.path(OUT_DIR, paste0(OUT_PREFIX, "_seq_matrix.rds")))
#   reference_df <- readRDS(file.path(OUT_DIR, paste0(OUT_PREFIX, "_reference_df.rds")))

ref_conflicts <- TaxaTools::find_taxonomy_conflicts(
  reference_df[, c("family", "genus", "species")],
  rank_system = c("family", "genus", "species")
)
if (nrow(ref_conflicts) > 0) {
  message("  Taxonomy conflicts in reference_df:")
  print(ref_conflicts)
} else {
  message("  No taxonomy conflicts in reference_df.")
}

# 6a.5. Detect and restore suppressed candidates ------------------------------
# BLAST 100%-rule drops sub-perfect hits when a perfect match exists.
# restore_suppressed_candidates() re-adds referenced congeners from reference_df
# so evaluate_likelihoods() can rank them against the best match.
# fetch_ncbi_reference_sequences() doesn't produce a taxon_name column (only
# the rank columns) -- derive it from species (full binomial; ecosystem
# convention -- see fill_higher_ranks()'s own @examples, and
# TaxaMatch::score_image_workflow.R Step 2's identical pattern).
reference_df$taxon_name <- TaxaTools::clean_taxon_names(reference_df$species)
detected <- TaxaLikely::detect_suppressed_candidates(match_obj)
if (detected$rule_detected)
  message(sprintf("  Rule(s) detected: %s", paste(detected$rules, collapse = ", ")))
match_obj_restored <- TaxaLikely::restore_suppressed_candidates(
  match_obj, reference_df,
  detected    = detected,
  rank_system = c("family", "genus", "species")
)

#!!!!!!!!!!
# Convert match taxonomy from NCBI to GBIF backbone so family/order names align
# with taxaexpect_priors and expansion_taxonomy (both use GBIF).
match_obj_restored <- TaxaMatch::convert_taxonomy_backbone(
  match_obj_restored,
  target_backbone_id = PRIOR_BACKBONE_ID,
  source_backbone_id = MATCH_BACKBONE_ID,
  rank_system        = c("order", "family", "genus", "species")
)

# 6b. Train likelihood model --------------------------------------------------
# score_transform = "sqrt_mismatch" (Session 158, TaxaLikely/CLAUDE.md): the
# package's original logit scale gets genus-tightness qualitatively backwards
# for unreferenced-relative (H2/H3) modeling -- a tight, hard-to-distinguish
# genus can show HIGHER logit-scale congener variance than a loose one, the
# opposite of the truth on the raw match-proportion scale, because logit's
# derivative diverges fastest exactly where real barcode matches concentrate
# (near 100% identity). Validated on real 12S congener data
# (PtConceptionWorkflow_12S_single_site.R, outside this monorepo); this
# template's own tiny bundled fixture is too small to re-validate the
# direction independently, but the underlying mechanism is a property of the
# transform, not of one specific dataset. H1's own fitting moves onto this
# scale too, since H1/H2/H3 are compared via density ratios at one shared
# point.
lik_model <- TaxaLikely::train_likelihood_model(
  raw_df          = seq_matrix,
  rank_system     = c("family", "genus", "species"),
  prior_weight    = 10.0,
  score_transform = "sqrt_mismatch"
)
TaxaLikely::interpret_model(lik_model)
.save(lik_model, "lik_model")

# 6b.5. Real per-observation read depth (evidence_col quality covariate) ------
# detections (Section 2.5) is reads_long already filtered to n_reads > 0 and
# relabeled to the ASV_N observation_id convention used by match_obj_restored
# -- used here as a real, non-circular per-observation quality signal (Session
# 155/156, TaxaLikely/CLAUDE.md): low-depth ASVs are noisier, so their H1 sigma
# can be selectively widened at inference time.
read_depth_per_obs <- detections |>
  dplyr::group_by(observation_id) |>
  dplyr::summarise(read_depth = sum(n_reads, na.rm = TRUE), .groups = "drop")
match_obj_restored <- match_obj_restored |>
  dplyr::left_join(read_depth_per_obs, by = "observation_id")

# 6b.6. Calibrate H1 to real query-vs-reference behavior ----------------------
# train_likelihood_model() estimates H1 entirely from reference-vs-reference
# pairs, which carry none of the technical noise (PCR/sequencing/degradation/
# ASV-inference) a real query picks up -- so a genuinely correct match routinely
# scores below the trained H1 mean, letting the unreferenced hypotheses
# out-compete the correct referenced species. calibrate_query_noise() estimates
# one marker-wide additive correction from observations whose species can be
# identified with high confidence from taxaexpect_priors' occurrence data
# (independent of match_obj's own scores, so this is non-circular), then shifts
# H1_Global_Mu and H1_Lookup$mu_score uniformly -- H2/H3 (defined relative to
# the shifted mean) move with it. Do not reuse this offset on a different
# marker/dataset -- re-estimate per workflow (see TaxaLikely/CLAUDE.md).
# evidence_col = "read_depth" additionally establishes the reference_evidence
# baseline that evaluate_likelihoods()'s evidence-based sigma rescale reads
# below. This template's tiny bundled fixture may not have enough confident
# observations to clear calibrate_query_noise()'s min_confident_obs default --
# if it warns and skips calibration, that's expected for this small a dataset,
# not a bug.
#
# offset_form = "constant" is requested deliberately, NOT the package-default
# affine ("linear") form: the bundled fixture has far too few referenced species
# to fit the affine slope, so "linear" would only fall back to "constant" with a
# warning. Real production workflows on adequately-referenced data should use the
# default "linear" (level-aware) recalibration -- see the PtConception/Mugu
# workflows and TaxaLikely supplemental methods Section 11A.
lik_model <- TaxaLikely::calibrate_query_noise(
  model_params = lik_model,
  match_df     = match_obj_restored,
  priors       = taxaexpect_priors,
  evidence_col = "read_depth",
  offset_form  = "constant"
)
.save(lik_model, "lik_model_calibrated")

# 6c. Evaluate likelihoods ----------------------------------------------------
# Session 121 (2026-06-26) inference improvements active by default:
#   alpha = 0.001  — score-only outlier filter (chi-sq, df=1): drops H1 candidates
#                    whose score is inconsistent with the species' own distribution
#                    (>3.3 sigma). Gap is intentionally excluded from this test — a
#                    small gap (confusable congener present) correctly lowers the
#                    bivariate H1 density without spuriously rejecting the candidate.
#   sigma floor    — per-species sigma floored at global sigma so tight reference
#                    clones (near-identical NCBI accessions) do not drive H1 to zero.
#   ratio_threshold = 0  — H1 rows gated solely by the alpha check above, not by
#                          comparison to H2/H3 likelihoods. Using ratio_threshold > 0
#                          creates a cross-rank comparison (H1 vs H2/H3 density) that
#                          can suppress legitimate but weak H1 matches.
# evidence_col/evidence_max_ratio add a parallel score_likelihood_evidence
# column (gated sigma rescale by real read depth) -- additive, does not change
# what feeds join_priors()/compute_posterior() downstream.
lik_result <- TaxaLikely::evaluate_likelihoods(
  match_df           = match_obj_restored,
  model_params       = lik_model,
  rank_system        = c("family", "genus", "species"),
  n_sims             = 200L,
  ratio_threshold    = 0,
  evidence_col       = "read_depth",
  evidence_max_ratio = 1
)
message(sprintf("  %d likelihood rows; %d unresolved ESVs.",
                nrow(lik_result$likelihoods),
                n_distinct(lik_result$unresolved$observation_id)))
.save(lik_result, "lik_result")

# Checkpoint: reload to skip 6a–6c on re-runs
# lik_result <- readRDS(file.path(OUT_DIR, paste0(OUT_PREFIX, "_lik_result.rds")))

# 6d. Coverage audit ----------------------------------------------------------
exclude_pred <- TaxaLikely::infer_exclude_predicted(match_obj)

coverage <- audit_barcode_coverage(
  reference_df[!duplicated(reference_df$species), c("genus", "species")],
  barcode_term      = BARCODE_TERM,
  target_rank       = "genus",
  exclude_predicted = !isFALSE(exclude_pred)
)
coverage$unreferenced <- TaxaTools::clean_taxon_names(coverage$unreferenced) |>
  (\(z) z[grepl("\\s", z)])()   # drop genus-only strings

# Diagnostic: species in both the match object and the unreferenced list signal
# a mismatch between BLAST (no length filter) and audit_barcode_coverage() (applies
# length filters). Do NOT remove — the H2 genus suppression rule handles any ASV
# where such a taxon is already H1, and global removal would also discard legitimate
# H2 candidates for ASVs where the taxon did not appear as a BLAST hit.
match_species <- unique(na.omit(match_obj$taxon_name))
in_both       <- intersect(coverage$unreferenced, match_species)
if (length(in_both) > 0L) {
  message(sprintf(
    "  NOTE — %d species appear in both the match object and the unreferenced list (BLAST found sequences not captured by audit filters — parameter mismatch): %s",
    length(in_both),
    paste(head(in_both, 5L), collapse = ", ")
  ))
}

print(coverage$census)
cat("Unreferenced species:\n"); print(coverage$unreferenced)

census_result <- mutate(coverage$census,
                        taxon_name = group,
                        rank       = "genus",
                        status     = ifelse(is_complete, "complete", "incomplete")
)
.save(census_result, "census_result")
.save(coverage,      "coverage")

# Checkpoint: reload to skip Step 6d on re-runs
# census_result <- readRDS(file.path(OUT_DIR, paste0(OUT_PREFIX, "_census_result.rds")))
# coverage      <- readRDS(file.path(OUT_DIR, paste0(OUT_PREFIX, "_coverage.rds")))
# inat_range is optional — load if available to skip the ~7-min API run. Real
# production workflows (e.g. PtConceptionWorkflow_12S.R) add this as an extra
# TaxaFetch::check_inat_range() + TaxaAssign::adjust_inat_range_priors() pair
# between Sections 7 and 8 below -- not included in this generic template to
# keep it runnable in seconds on the tiny example data; add it when adapting
# this template to a real study with taxa iNaturalist actually has range data for.
# inat_range_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_inat_range.rds"))
# if (file.exists(inat_range_path)) inat_range <- readRDS(inat_range_path)

# =============================================================================
# 7.  POSTERIOR ASSIGNMENT (TaxaAssign)
# =============================================================================
# join_priors() bridges TaxaLikely's likelihood object to TaxaExpect's prior
# table (dark-diversity fallback for any candidate without a modelled prior;
# Session 138 -- its final dedup now preserves one row per site, instead of
# collapsing a multi-site observation to one row per candidate).
# combine_multisite_priors() (Session 138) combines those per-site rows for
# any observation_id detected at more than one real site (e.g. the same eDNA
# ASV recovered from reads at two different sample sites in Reads_Table) via
# precision-weighted logit combination -- a site with little occurrence data
# is discounted relative to a well-supported one, rather than treated as
# equally reliable. Single-site observations (still the common case for this
# template's bundled test data) pass through unchanged. compute_posterior()
# runs the Bayes update, posterior_consensus() collapses each observation_id
# to one LCA-based row, update_prior_from_consensus() lets confirmed species
# from OTHER observations in the SAME multi-member spatial group nudge priors
# for that group's still-unresolved observations (explicitly skipped for
# single-observation groups via spatial_group_map -- see TaxaAssign/CLAUDE.md's
# Session 134 note), and add_slash_taxon() appends the compact reporting
# labels (slash_taxon_name / consensus_OTU / primary_taxon).
# =============================================================================

# taxonomy_lookup: distinct taxon_name x rank x taxonomy.
# NOTE (corrected): TaxaLikely::evaluate_likelihoods()'s own documented
# $likelihoods columns are observation_id/taxon_name/taxon_name_rank/
# hypothesis_type/score_likelihood* only -- family/genus are NOT carried
# through on this (sequence/BLAST) pathway, unlike the image/acoustic
# pathway's assign_scores() output. Build taxonomy_lookup from
# match_obj_restored instead (the real BLAST match object, still in scope,
# with family/genus/species from the GBIF-backbone-verified taxonomy join in
# Section 1 and taxon_name/taxon_name_rank from create_taxon_names()). This
# only covers specific_candidate taxa (H2/H3 unreferenced placeholder names
# are synthesized inside evaluate_likelihoods() and were never in the input
# match object) -- join_priors()'s dark-diversity fallback is the intended
# mechanism for those, not this lookup.
taxonomy_lookup <- match_obj_restored |>
  dplyr::distinct(taxon_name, taxon_name_rank, genus, family)

# site_for_join (Section 5): one row per (observation_id, site) -- usually one
# row per observation_id, but a genuine multi-site observation (Session 138
# fix) now correctly produces one row PER SITE -- join_priors()'s multi-site
# data-frame path, so every observation is joined against the priors
# generated for ITS OWN site(s), not one global site or an averaged
# centroid.
likelihoods_w_prior <- TaxaAssign::join_priors(
  likelihoods       = lik_result$likelihoods,
  taxaexpect_priors = taxaexpect_priors,
  site              = site_for_join,
  taxonomy_lookup   = taxonomy_lookup,
  rank_system       = fgs,
  backbone_id       = PRIOR_BACKBONE_ID
)
.save(likelihoods_w_prior, "likelihoods_w_prior")

# Combine per-site prior rows for any observation detected at more than one
# site (no-op for single-site observations -- see Section 7 header note).
likelihoods_w_prior_combined <- TaxaAssign::combine_multisite_priors(
  joined = likelihoods_w_prior
)
.save(likelihoods_w_prior_combined, "likelihoods_w_prior_combined")

posterior_df <- TaxaAssign::compute_posterior(
  likelihood_w_prior = likelihoods_w_prior_combined,
  n_sims             = 1000
)
.save(posterior_df, "posterior_df")

consensus_df <- TaxaAssign::posterior_consensus(
  posterior_df        = posterior_df,
  rank_system         = fgs
)

# Refine priors for still-unresolved observations using confirmed-present
# species from OTHER observations that share their spatial group (never
# across unrelated single-observation groups -- spatial_group_map enforces
# this; see TaxaAssign::update_prior_from_consensus()'s own guard). Re-run
# posterior_consensus() afterward so consensus_df reflects the refined
# posteriors.
posterior_df_refined <- TaxaAssign::update_prior_from_consensus(
  result            = posterior_df,
  consensus         = consensus_df,
  spatial_group_map = site_table,
  n_sims            = 1000
)
.save(posterior_df_refined, "posterior_df_refined")

consensus_df <- TaxaAssign::posterior_consensus(
  posterior_df        = posterior_df_refined,
  rank_system         = fgs
)

# add_posthoc_assessment() needs a taxon x tier lookup -- taxaexpect_priors
# already has taxon_name + model_tier (tier1/tier2/tier3_undetected) from
# Section 5, so it can be passed directly as `tiers`.
# absolute_fit_pvalue_col (default "winner_absolute_fit_pvalue", already
# present from posterior_consensus()'s pass-through): informational only,
# safe unconditionally (never changes consensus_taxon/consensus_rank).
consensus_df <- TaxaFlag::add_posthoc_assessment(
  consensus_df = consensus_df,
  tiers        = taxaexpect_priors
)

taxaassign_consensus <- TaxaAssign::add_slash_taxon(consensus_df)
.save(taxaassign_consensus, "taxaassign_consensus")

message(sprintf("  %d observation(s); %d resolved; %d irreducible consensus call(s).",
                nrow(taxaassign_consensus),
                sum(taxaassign_consensus$is_resolved, na.rm = TRUE),
                sum(taxaassign_consensus$irreducible_consensus, na.rm = TRUE)))
print(taxaassign_consensus)

# Optional: add common names for reporting (uses REVIEW_CONTEXT$geography as a
# location hint; falls back to the un-localized common name if unavailable).
taxaassign_consensus$common_name <- TaxaTools::scientific_to_common(
  taxaassign_consensus$consensus_taxon,
  location = REVIEW_CONTEXT$geography
)$common_name

# Checkpoint: reload to skip Step 7 on re-runs
# taxaassign_consensus <- readRDS(file.path(OUT_DIR, paste0(OUT_PREFIX, "_taxaassign_consensus.rds")))

# =============================================================================
# 8.  QUALITY REVIEW (TaxaFlag)
# =============================================================================
# review_assignments() is a real LLM call: for each irreducible_consensus
# candidate, asks whether the assignment is plausible given habitat/geography/
# contamination/taxonomic-scope context. llm_fn passed explicitly (see TaxaID/
# CLAUDE.md's .resolve_llm_fn() footgun -- fully-namespaced calls never trigger
# TaxaTools::.onAttach()'s auto-detection).
# =============================================================================

reviewed_assignments <- TaxaFlag::review_assignments(
  df               = taxaassign_consensus,
  taxon_col        = "consensus_taxon",
  taxon_rank_col   = "consensus_rank",
  irreducible_only = TRUE,
  context          = REVIEW_CONTEXT,
  llm_fn           = getOption("TaxaID.llm_fn", TaxaTools::call_anthropic_api)
)
.save(reviewed_assignments, "reviewed_assignments")

flag_summary <- TaxaFlag::report_flags(reviewed_assignments)
print(flag_summary)

message("\nWorkflow complete: taxaassign_consensus / reviewed_assignments are the ",
        "final outputs. See flag_summary for the QC roll-up.")

# =============================================================================
# NOTES FOR ADAPTING THIS TEMPLATE TO A NEW DATASET / DATA TYPE
# =============================================================================
# - Section 1 assumes DNA/BLAST input. For image or acoustic classifier output,
#   swap Section 1 for TaxaMatch::score_image_inat() / read_birdnet_output()
#   (see TaxaMatch's own inst/workflows/score_image_workflow.R /
#   score_acoustic_workflow.R) and skip straight to a likelihood object via
#   TaxaLikely::unreferenced_candidates() + assign_scores() -- no
#   build_sequence_matrix()/train_likelihood_model() training step needed,
#   since those classifiers are already pre-trained (see TaxaLikely/CLAUDE.md).
# - Section 4 (habitat) and Section 5 (TaxaExpect priors) are data-type
#   agnostic once you have an occurrences_clean table with taxon_name +
#   coordinates -- no changes needed for image/acoustic data types.
# - Section 2.5 (site table + spatial grouping): the DNA/BLAST site_df built
#   there (every observation placed at one hardcoded STUDY_LAT/STUDY_LON) is
#   this pathway's own placeholder, not a generic pattern. The image pathway
#   (score_image_inat() output) already carries real per-observation lat/lng
#   embedded in the match object, so build_site_table() there needs no
#   site_df at all -- call it directly on the match object. The acoustic
#   pathway has the same site-table gap as DNA/BLAST (read_birdnet_output()
#   carries no site metadata either) -- see Phase 4 of the reentry plan below.
# - Where this template most likely needs a NEW function or wrapper rather
#   than just parameter changes: (1) a single high-level function spanning
#   Section 6 for the non-sequence data types (TaxaLikely::compute_likelihoods()
#   already does part of this for the sequence path -- an analogous wrapper
#   for image/acoustic would collapse unreferenced_candidates() + assign_scores()
#   into one call); (2) Section 7/8's join_priors -> compute_posterior ->
#   posterior_consensus -> add_slash_taxon -> add_posthoc_assessment chain is
#   already covered by TaxaAssign::run_bayesian_pipeline() for the common case --
#   consider swapping Section 7 for that wrapper once this template's shape is
#   confirmed to match what run_bayesian_pipeline() assumes.
# - Multi-site / multi-habitat studies: Sections 2.5, 3, 5, and 7 now branch
#   per spatial_group_id (see ecosystem_docs/REENTRY_PROMPT_session137_
#   observation_pipeline_wiring.md, Phase 2) rather than resolving one focal
#   SITE_GRID_ID for the whole run. Section 2.5's SAMPLE_SITE_METADATA (Phase
#   4, DNA/BLAST half) now supplies genuinely different real coordinates per
#   Reads_Table sample column via TaxaMatch::join_event_site_metadata() --
#   swap it for your own study's real sample-to-site lookup table. One known,
#   deliberately-deferred gap this surfaced (see SAMPLE_SITE_METADATA's own
#   comment and Phase 5): an ASV with real reads at more than one sample
#   resolves to one spatial_group_id with multiple site rows, which
#   Section 3 now routes to the pooled multi-member branch as a reasonable
#   fallback -- not the fully-correct per-(observation_id, site) treatment,
#   which is Phase 5's job. The acoustic pathway's equivalent site-metadata
#   join is NOT wired here (no real multi-site BirdNET deployment data exists
#   yet to wire against honestly) -- see score_acoustic_workflow.R's own note.
