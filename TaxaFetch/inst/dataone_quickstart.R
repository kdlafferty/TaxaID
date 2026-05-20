# ==============================================================================
# dataone_quickstart.R
# TaxaFetch — DataONE quickstart: fetch a known dataset and inspect results
#
# PURPOSE
# ───────
# Demonstrates the core fetch pipeline using a single well-known dataset.
# No LLM calls, no catalog harvest, no checkpoints. Runs in ~2 minutes.
#
# Use this to:
#   • Verify your TaxaFetch installation is working
#   • Understand the output structure before running the full workflow
#   • Experiment with fetch parameters
#
# For the full geo + taxon screening pipeline, see Dataone_workflow.R.
#
# REQUIREMENTS
# ────────────
# devtools::load_all() or library(TaxaFetch) after devtools::install()
# Internet connection (fetches from pasta.lternet.edu)
#
# DATASET USED
# ────────────
# edi.885.1 — SBC LTER: Reef: Kelp Forest Community Dynamics: Fish abundance
# ~50k occurrence records, 5 reef sites, Santa Barbara Channel
# Structure: DwC Archive (event table + occurrence table joined on id)
# ==============================================================================


# ==============================================================================
# STEP 0 — Load package
# ==============================================================================

rm(list = ls())
devtools::load_all()   # or: library(TaxaFetch)

# Target area — Santa Barbara Channel
bbox <- c(-120.5, -119.3, 33.8, 34.5)   # c(west, east, south, north)


# ==============================================================================
# STEP 1 — Fetch a single known dataset
#
# edi.885.1 is a Darwin Core Archive with two tables:
#   event      — sampling events with coordinates (~121k rows)
#   occurrence — species records linked to events (~50k rows)
#
# The pipeline joins them automatically on the shared 'id' column.
# timeout = 120L is sufficient; the event table is ~30MB.
# ==============================================================================

occ <- fetch_dataone_occurrences("edi.885.1", bbox, timeout = 120L)


# ==============================================================================
# STEP 2 — Inspect the result
# ==============================================================================

cat(sprintf("\nRecords returned: %d\n", nrow(occ)))
cat(sprintf("Unique taxa:      %d\n", dplyr::n_distinct(occ$scientificName,
                                                         na.rm = TRUE)))
cat(sprintf("Date range:       %s to %s\n",
            min(occ$eventDate, na.rm = TRUE),
            max(occ$eventDate, na.rm = TRUE)))
cat(sprintf("Lat range:        %.3f to %.3f\n",
            min(occ$decimalLatitude,  na.rm = TRUE),
            max(occ$decimalLatitude,  na.rm = TRUE)))
cat(sprintf("Lon range:        %.3f to %.3f\n",
            min(occ$decimalLongitude, na.rm = TRUE),
            max(occ$decimalLongitude, na.rm = TRUE)))

# ── Top taxa by record count ──────────────────────────────────────────────────
cat("\nTop 15 taxa by record count:\n")
occ |>
  dplyr::count(scientificName, sort = TRUE) |>
  dplyr::slice_head(n = 15) |>
  print()

# ── Records per year ──────────────────────────────────────────────────────────
cat("\nRecords per year:\n")
occ |>
  dplyr::mutate(year = substr(eventDate, 1, 4)) |>
  dplyr::count(year, sort = FALSE) |>
  print(n = 30)

# ── First few rows ────────────────────────────────────────────────────────────
cat("\nFirst 6 rows (key DwC columns):\n")
occ |>
  dplyr::select(dplyr::any_of(c(
    "occurrenceID", "datasetID", "eventDate",
    "decimalLatitude", "decimalLongitude",
    "scientificName", "individualCount"
  ))) |>
  head(6) |>
  print()

# Show which abundance/count column is present (varies by dataset structure)
abund_cols <- intersect(
  c("individualCount", "value", "count", "abundance"),
  names(occ)
)
if (length(abund_cols) > 0L) {
  cat(sprintf("\nAbundance column: '%s'\n", abund_cols[1]))
  cat(sprintf("Non-zero records: %d of %d (%.1f%%)\n",
              sum(occ[[abund_cols[1]]] > 0, na.rm = TRUE),
              nrow(occ),
              100 * mean(occ[[abund_cols[1]]] > 0, na.rm = TRUE)))
} else {
  cat("\nNo abundance column detected — presence-only dataset.\n")
}


# ==============================================================================
# STEP 3 — Try an ODM dataset (ecocomDP structure)
#
# edi.189.2 — SBC LTER: Kelp Forest Community Dynamics: Fish abundance
# Same fish data but packaged in the LTER Observation Data Model format.
# Three tables joined automatically: observation + location + taxon.
# variable_name in this dataset is "COUNT" (not the default "DENSITY") so
# the pipeline falls back to all rows.
# ==============================================================================

cat("\n\n── ODM dataset example ────────────────────────────────────────────\n")
occ_odm <- fetch_dataone_occurrences("edi.189.2", bbox, timeout = 120L)

cat(sprintf("\nODM records returned: %d\n", nrow(occ_odm)))
cat(sprintf("Unique taxa:          %d\n",
            dplyr::n_distinct(occ_odm$scientificName, na.rm = TRUE)))

# Confirm the same taxa appear in both datasets
shared <- intersect(
  unique(occ$scientificName),
  unique(occ_odm$scientificName)
)
cat(sprintf("Taxa shared with DwC-A dataset: %d of %d\n",
            length(shared),
            dplyr::n_distinct(occ_odm$scientificName, na.rm = TRUE)))


# ==============================================================================
# STEP 4 — What to do next
# ==============================================================================

cat("
─────────────────────────────────────────────────────────────────────────────
NEXT STEPS
─────────────────────────────────────────────────────────────────────────────

1. Run the full discovery pipeline (Dataone_workflow.R) to find all relevant
   datasets for your bbox and taxon group — not just these two known datasets.

2. Merge with GBIF data using rename_cols() + stack_occurrences() in TaxaFetch,
   then assign habitats with build_habitat_prompt() and the LLM pipeline.

3. Filter to high-quality detections before modelling:
     occ_clean <- occ |> dplyr::filter(individualCount > 0)

4. For large event tables (>100MB), increase timeout:
     fetch_dataone_occurrences('edi.970.1', bbox, timeout = 600L)

5. For datasets with non-standard site labels, supply a coordinate lookup:
     fetch_dataone_occurrences('knb-lter-sbc.39.5', bbox,
       site_lookup = data.frame(
         site_code        = c('BC I', 'BC II', 'Fern 1', ...),
         decimalLatitude  = c(...),
         decimalLongitude = c(...)
       ))
─────────────────────────────────────────────────────────────────────────────
")
