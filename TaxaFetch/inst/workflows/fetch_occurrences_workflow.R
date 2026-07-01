# ==============================================================================
# WORKFLOW: FETCH OCCURRENCE DATA (TaxaFetch)
# ==============================================================================
# Purpose: Resolve a taxon list to GBIF usage keys, fetch occurrence records
#   within a search area, quality-filter them, and stack them into a single
#   standardized occurrence table.
#
# Audience: someone learning TaxaFetch step by step. With DEBUG_MODE = TRUE
#   (the default) this script runs top-to-bottom in well under a minute using
#   a small built-in example (genus Gadus, North Atlantic) -- no private lab
#   data required. Just source() the whole file.
#
# TWO VARIANTS -- activate one, comment out the other:
#   VARIANT A -- NARROW MARKER
#     Single GBIF fetch covering the marker's target group only. Recommended
#     when the marker has a well-defined taxonomic scope (e.g. MiFish-U
#     amplifies fish + some marine mammals).
#   VARIANT B -- BROAD MARKER
#     GBIF fetch at a higher rank + placeholder for additional non-GBIF
#     sources (e.g. benthic survey data underrepresented in GBIF for markers
#     like 18S/COI). Sampling_group assignment (grouping taxa for per-group
#     modelling) is intentionally NOT included here -- see the TODO comment
#     in VARIANT B below.
#
# Output: all_occurrences -- a tibble; see "Output" block at the end of this
#   file for the full column contract consumed by TaxaHabitat.
# ==============================================================================

# --- Namespaces used in this script (loaded, never attached) ----------------
# TaxaFetch::, TaxaTools::, dplyr::, tibble::

# ==============================================================================
# CONFIG
# ==============================================================================
# Parameters are grouped here so this script's body can become a wrapper
# function's implementation with minimal changes -- each CONFIG value maps
# to a future function argument.

# DEBUG_MODE = TRUE  -> small built-in tutorial example (Gadus, North Atlantic)
# DEBUG_MODE = FALSE -> plug in your own taxon list / coordinates (see the
#                       "SWAP IN YOUR OWN DATA" block below Section 1)
DEBUG_MODE <- TRUE

# GBIF two-path dispatch threshold. fetch_gbif_occurrences() (real-time,
# per-key) is preferred below this many keys; download_gbif_occurrences()
# (async bulk download, requires a GBIF account) is preferred at or above it.
# See Section 2 for the dispatch itself.
GBIF_SMALL_QUERY_THRESHOLD <- 50L

if (DEBUG_MODE) {

  # ---- Tutorial example: genus Gadus (cod), North Atlantic -------------------
  STUDY_TAXA     <- tibble::tibble(genus = "Gadus")
  STUDY_LAT      <- 60.0     # North Sea / Norwegian Sea
  STUDY_LON      <- 2.0
  STUDY_RADIUS   <- 2.0      # degrees -- modest box, keeps the example fast
  YEAR_RANGE     <- "2015,2024"
  GBIF_LIMIT     <- 500L     # small per-key cap -- this is a tutorial run

} else {

  # ==========================================================================
  # >>> SWAP IN YOUR OWN DATA <<<
  # ==========================================================================
  # Replace the block above with your real study parameters:
  #
  #   STUDY_TAXA   <- match_obj |> dplyr::distinct(family) |>
  #                     dplyr::filter(!is.na(family))
  #     (or genus/species -- one row per taxon, columns named for Linnaean
  #     ranks; see ?TaxaFetch::get_keys_from_context)
  #
  #   STUDY_LAT    <- 34.4      # your site's centre latitude
  #   STUDY_LON    <- -119.7    # your site's centre longitude
  #   STUDY_RADIUS <- 1.0       # degrees -- real studies typically need a
  #                             # larger radius than the tutorial example;
  #                             # consider TaxaFetch::define_search_polygon()
  #                             # for an irregular coastline instead of a
  #                             # square box
  #   YEAR_RANGE   <- "2000,2024"
  #   GBIF_LIMIT   <- 10000L
  #
  # Set DEBUG_MODE <- FALSE above and fill in the values here.
  # ==========================================================================
  stop("DEBUG_MODE is FALSE but no real study parameters have been supplied. ",
       "Edit the 'SWAP IN YOUR OWN DATA' block in this script.")
}

# Output location for checkpoint files (see explicit-checkpoint pattern below)
OUT_DIR    <- tempdir()
OUT_PREFIX <- "tutorial_gadus"

message(sprintf("DEBUG_MODE = %s -- %s", DEBUG_MODE,
                if (DEBUG_MODE) "using built-in tutorial example (Gadus)"
                else "using user-supplied study parameters"))

# ==============================================================================
# 1.  DEFINE THE SEARCH AREA AND RESOLVE TAXON KEYS
# ==============================================================================

message("\n--- Step 1: Defining search area and resolving GBIF keys ---")

# make_bbox_wkt() builds a square WKT bounding box (scripted, non-interactive)
# -- fine for a tutorial box. For a real study with an irregular coastline,
# TaxaFetch::define_search_polygon() (interactive; requires shiny/miniUI/
# leaflet) usually wastes less GBIF download bandwidth over land/open ocean.
bbox <- TaxaFetch::make_bbox_wkt(
  lat        = STUDY_LAT,
  lon        = STUDY_LON,
  radius_deg = STUDY_RADIUS
)

# get_keys_from_context() resolves the taxon list to GBIF usage keys, using
# the full taxonomic hierarchy supplied in STUDY_TAXA to avoid homonym errors.
taxa_keys  <- TaxaFetch::get_keys_from_context(STUDY_TAXA)
valid_keys <- taxa_keys$usageKey[!is.na(taxa_keys$usageKey)]

message(sprintf("  %d of %d taxa resolved to valid GBIF keys.",
                length(valid_keys), nrow(taxa_keys)))
if (length(valid_keys) == 0) {
  stop("No GBIF keys resolved -- check STUDY_TAXA spelling/rank columns.")
}

# ---- Explicit checkpoint (not automatic) ------------------------------------
# Save now so a future session can skip Step 1 by pasting the readRDS() line
# below -- no file.exists()-gated auto-reload; you decide when to reuse this.
valid_keys_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_valid_keys.rds"))
saveRDS(valid_keys, valid_keys_path)
message(sprintf("  Saved: %s", valid_keys_path))
message(sprintf("  To reuse without re-resolving keys, paste:\n    valid_keys <- readRDS(\"%s\")",
                valid_keys_path))

# ==============================================================================
# 2.  FETCH GBIF OCCURRENCES -- TWO-PATH DISPATCH
# ==============================================================================
# fetch_gbif_occurrences()    -- real-time, per-key. Best for < ~50 keys.
#                                 No GBIF account needed.
# download_gbif_occurrences() -- async bulk download. Best for >= 50 keys or
#                                 to avoid per-key rate limits. Requires a
#                                 free GBIF account (GBIF_USER/GBIF_PWD/
#                                 GBIF_EMAIL in ~/.Renviron).
#
# This dispatch is fully deterministic on a value you already have in hand
# (the resolved key count) -- not hidden-state-dependent branching.

message("\n--- Step 2: Fetching GBIF occurrences ---")

if (length(valid_keys) < GBIF_SMALL_QUERY_THRESHOLD) {

  message(sprintf(
    "  %d keys < GBIF_SMALL_QUERY_THRESHOLD (%d) -> using fetch_gbif_occurrences() (real-time, no GBIF account needed).",
    length(valid_keys), GBIF_SMALL_QUERY_THRESHOLD
  ))
  raw_gbif <- TaxaFetch::fetch_gbif_occurrences(
    keys       = valid_keys,
    geometry   = bbox,
    year_range = YEAR_RANGE,
    limit      = GBIF_LIMIT
  )

} else {

  message(sprintf(
    "  %d keys >= GBIF_SMALL_QUERY_THRESHOLD (%d) -> using download_gbif_occurrences() (async bulk download, requires GBIF account).",
    length(valid_keys), GBIF_SMALL_QUERY_THRESHOLD
  ))
  raw_gbif <- TaxaFetch::download_gbif_occurrences(
    keys       = valid_keys,
    geometry   = bbox,
    year_range = YEAR_RANGE,
    limit      = GBIF_LIMIT,
    basis_keep = c("HUMAN_OBSERVATION", "MACHINE_OBSERVATION"),
    overwrite  = TRUE
  )

}

message(sprintf("  %d raw records fetched.", nrow(raw_gbif)))

# ---- Explicit checkpoint ----------------------------------------------------
raw_gbif_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_raw_gbif.rds"))
saveRDS(raw_gbif, raw_gbif_path)
message(sprintf("  Saved: %s", raw_gbif_path))
message(sprintf("  To reuse without re-fetching, paste:\n    raw_gbif <- readRDS(\"%s\")",
                raw_gbif_path))

# ==============================================================================
# 3.  QUALITY-FILTER AND STANDARDIZE
# ==============================================================================
# TWO VARIANTS -- activate one, comment out the other.
# ==============================================================================

message("\n--- Step 3: Quality-filtering and standardizing occurrences ---")

# --- VARIANT A: NARROW MARKER -------------------------------------------------
# Single GBIF fetch already covers the marker's target group. No additional
# non-GBIF sources are added.

gbif_occurrences <- raw_gbif |>
  TaxaFetch::filter_gbif_quality(
    max_coord_uncertainty    = 500,
    max_coord_decimal_places = 2
  )

if (nrow(gbif_occurrences) == 0) {
  stop("No GBIF records survived quality filtering -- check STUDY_RADIUS, ",
       "YEAR_RANGE, or loosen filter_gbif_quality() thresholds.")
}

all_occurrences <- TaxaFetch::stack_occurrences(gbif_occurrences)
message(sprintf("  %d occurrence records retained (Variant A).", nrow(all_occurrences)))

# --- END VARIANT A ------------------------------------------------------------


# --- VARIANT B: BROAD MARKER -- uncomment to activate -------------------------
# Replaces VARIANT A above (comment out VARIANT A when using this).
#
# Key differences from VARIANT A:
#   1. GBIF keys are resolved at a higher rank (order/class) to capture the
#      full taxonomic breadth of a broad-spectrum marker.
#   2. require_species = TRUE is passed to filter_gbif_quality() because
#      broad-rank queries return many genus/family-only records that lack a
#      species value and are unusable downstream.
#   3. Additional non-GBIF sources would be loaded, standardized to match
#      gbif_std's columns, and stacked alongside it.
#
# TODO: sampling_group assignment (grouping taxa for per-group modelling,
#   e.g. macroalgae vs. zooplankton vs. fish) is being redesigned as a
#   reusable classification step -- separate design thread, not part of this
#   file. For now the broad-marker path stops after stack_occurrences().
#   See memory/project_workflow_propagation_list.md for status.

# gbif_occurrences_b <- raw_gbif |>
#   TaxaFetch::filter_gbif_quality(
#     max_coord_uncertainty    = 500,
#     max_coord_decimal_places = 2,
#     require_species          = TRUE   # broad markers return many coarse-rank rows
#   )
#
# gbif_rank_cols <- intersect(
#   c("kingdom", "phylum", "class", "order", "family", "genus", "species"),
#   names(gbif_occurrences_b)
# )
# gbif_std <- gbif_occurrences_b |>
#   TaxaTools::create_taxon_names(rank_system = gbif_rank_cols) |>
#   dplyr::filter(taxon_name_rank == "species") |>
#   dplyr::select(dplyr::any_of(c("decimalLatitude", "decimalLongitude",
#                                  "taxon_name", "phylum", "class", "order",
#                                  "family", "genus", "species")))
# gbif_std$taxon_name <- TaxaTools::clean_taxon_names(gbif_std$taxon_name)
# gbif_std$datasource <- "GBIF"
#
# # Additional non-GBIF sources: load, standardize to gbif_std's columns
# # (decimalLatitude, decimalLongitude, taxon_name, phylum, class, order,
# # family, genus, species, datasource), then stack.
# # extra_source <- read.csv("my_additional_occurrences.csv")
# # extra_source$datasource <- "MySource"
#
# all_occurrences <- TaxaFetch::stack_occurrences(gbif_std)  # add extra_source here once standardized
# message(sprintf("  %d occurrence records retained (Variant B).", nrow(all_occurrences)))
#
# # TODO: sampling_group assignment goes here in a future session -- see note above.

# --- END VARIANT B -------------------------------------------------------------

# ---- Explicit checkpoint -----------------------------------------------------
all_occurrences_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_all_occurrences.rds"))
saveRDS(all_occurrences, all_occurrences_path)
message(sprintf("  Saved: %s", all_occurrences_path))
message(sprintf("  To reuse without re-fetching/re-filtering, paste:\n    all_occurrences <- readRDS(\"%s\")",
                all_occurrences_path))

message("\nWorkflow complete.")
message("Next: pass all_occurrences to TaxaHabitat for habitat assignment.")

# ==============================================================================
# Output
# ==============================================================================
# This workflow produces one object: all_occurrences (a tibble).
#
# Columns (Variant A -- unmodified GBIF columns plus point_id):
#   point_id             -- character; unique per lat/lon pair (added by
#                           stack_occurrences())
#   decimalLatitude      -- numeric
#   decimalLongitude     -- numeric
#   species, genus, family, order, class, phylum, kingdom
#                        -- character; GBIF taxonomic columns (as returned)
#   ... plus other standard GBIF occurrence columns (basisOfRecord, year,
#       occurrenceStatus, coordinateUncertaintyInMeters, etc.)
#
# Columns (Variant B -- standardized subset, once uncommented):
#   point_id, decimalLatitude, decimalLongitude, taxon_name,
#   phylum, class, order, family, genus, species, datasource
#
# Consumer: TaxaHabitat, which assigns a habitat class per taxon_name /
#   species using all_occurrences' taxonomy + coordinate columns.
# ==============================================================================
