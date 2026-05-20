# =============================================================================
# WORKFLOW: COMBINING OCCURRENCE SOURCES
# TaxaFetch — Session template
# =============================================================================
#
# PURPOSE:
#   Merge two or more occurrence data frames into a single standardised (std) frame
#   ready for habitat assignment and modelling. Standardization aligns backbones,
#   column names, taxon_name, and creates a unique point_id. This gets data ready for
#   habitat assignment.
#
# PIPELINE POSITION:
#   Runs after each source has been individually quality-filtered.
#   Output feeds into: build_habitat_prompt() → assign_habitat_biological()
#
# KEY STEPS:
#   0. User inputs
#   1. Prepare each source:
#        a. Create taxon_name column (create_taxon_names)
#        b. Verify names against a taxonomic backbone (verify_taxon_names)
#        c. Rename columns to a common convention (rename_to_dwc)
#        d. Tag datasource column
#   2. Stack all sources (stack_occurrences)
#
# NOTES:
#   - Repeat Step 1 for every additional source before calling stack_occurrences
#   - rename_cols() only renames — it does not drop or reorder columns
#   - All sources must share the same lat/lon column names before stacking;
#     the defaults are "decimalLatitude" and "decimalLongitude" (DarwinCore)
#   - stack_occurrences() will error if coordinate columns are missing,
#     catching a forgotten rename before it silently produces NA coordinates
#   - point_id is created automatically by stack_occurrences()
#   - Tag your GBIF data with datasource = "GBIF" before stacking so that
#     record provenance is preserved throughout the pipeline
#
# DEPENDENCIES:
#   TaxaFetch, TaxaTools, dplyr
# =============================================================================

library(TaxaFetch)
library(TaxaTools)
library(dplyr)

# =============================================================================
# 0.  USER INPUTS
# =============================================================================
# Edit this section for your project. Add or remove source blocks as needed.
# At minimum supply one GBIF source and one supplemental source; if you only
# have GBIF data, skip to Step 2 and pass gbif_std alone to stack_occurrences()
# (though combining a single frame is not necessary — just use it directly).
# =============================================================================


# =============================================================================
# 1a.  PREPARE GBIF SOURCE
# =============================================================================

# Assumes gbif_occurrences is already in your environment from the GBIF
# retrieval workflow (fetch_gbif_occurrences → filter_gbif_quality).

# Determine rank columns present in the GBIF download.
# Adjust this vector if your GBIF data uses different rank column names.
gbif_rank_cols <- intersect(
  c("kingdom", "phylum", "class", "order", "family", "genus", "species"),
  names(gbif_occurrences)
)

gbif_std <- occurrences_clean |>
  create_taxon_names(taxonomy_ranks = gbif_rank_cols) |>
  filter(taxon_name_rank == "species")        # keep species-rank records only

gbif_std$datasource <- "GBIF"                 # tag provenance — do not skip


# =============================================================================
# 1b.  PREPARE SUPPLEMENTAL SOURCE  (repeat this block for each extra source)
# =============================================================================

# --- Raw supplemental data ---------------------------------------------------
# Replace with your actual data frame. Column names do not need to match GBIF
# at this stage — rename_cols() handles that below.
# Specify whichever rank columns are present in your supplemental data.
supp_rank_cols <- c("Family", "Genus", "Species")   # edit as needed

additional_data <- data.frame(
  Family     = "Gobiidae",
  Genus      = "Clevelandia",
  Species    = "Clevelandia ios",
  Latitude   = 34.11167,
  Longitude  = -119.081667,
  SurveyDate = "1 Jan 2022",
  site       = "Carpinteria",
  datasource = "govreport",
  stringsAsFactors = FALSE
)|>
  create_taxon_names(taxonomy_ranks = supp_rank_cols)

# --- Create taxon_name -------------------------------------------------------

# --- Verify names against the GBIF backbone (backbone_id 11) -----------------
# This resolves synonyms and confirms the name is recognised.
verified <- verify_taxon_names(additional_data$taxon_name, backbone_id = 11)

# Extract the rank vector used by the GBIF backbone for this taxonomic group.
GBIF_ranks <- strsplit(verified$classification_ranks, "\\|")[[1]]

# Rebuild taxon_name using GBIF backbone ranks so it aligns with gbif_std.
additional_data_std <- verified |>
  change_backbone(
    input_col          = "user_supplied_name",
    old_backbone_label = "taxon_name",
    new_backbone_label = "gbif_name"
  ) |>
  left_join(additional_data)    # re-attach original columns

# --- Rename columns to DarwinCore convention ---------------------------------
# Map supplemental column names → DarwinCore (or GBIF) equivalents.
# Only list columns whose names differ from the target convention.
additional_data_std <- rename_cols(
  df    = additional_data_std,
  col_map = c(
    "Latitude"   = "decimalLatitude",
    "Longitude"  = "decimalLongitude",
    "SurveyDate" = "eventDate",
    "site"       = "verbatimLocality"
  )
)

# datasource column already present ("govreport") — no need to reassign.
# If your supplemental data has no datasource column, add one here:
# additional_data_std$datasource <- "my source label"


# =============================================================================
# 2.  STACK ALL SOURCES
# =============================================================================
# Add all prepared frames as arguments. stack_occurrences() will:
#   - Check coordinate columns are present in every frame
#   - bind_rows() all frames (columns aligned by name; missing = NA)
#   - Add point_id (decimalLatitude_decimalLongitude)

occurrence_data <- stack_occurrences(
  gbif_std,
  additional_data_std
  # add further prepared frames here, e.g.:
  # edna_2023_std,
  # museum_records_std
)

# Quick check
message(sprintf(
  "Sources present: %s",
  paste(sort(unique(occurrence_data$datasource)), collapse = ", ")
))
message(sprintf("Total records:   %d", nrow(occurrence_data)))
message(sprintf("Unique taxa:     %d", n_distinct(occurrence_data$taxon_name)))

saveRDS(occurrence_data,
        file.path(system.file("", package = "TaxaFetch"), "occurrence_data.rds"))
message("Saved occurrence_data.")

# occurrence_data is ready for:
#   build_habitat_prompt(unique(occurrence_data$taxon_name))
