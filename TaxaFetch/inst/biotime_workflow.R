# ==============================================================================
# biotime_workflow.R
# TaxaFetch — BioTime occurrence acquisition workflow
#
# BioTime (https://biotime.st-andrews.ac.uk) is a global database of
# biodiversity time-series. Data are distributed as per-study CSVs and
# must be downloaded manually — there is no query API.
#
# HOW TO GET BIOTIME DATA
# -----------------------
# 1. Go to https://biotime.st-andrews.ac.uk/home.php
# 2. Register for a free account
# 3. Browse or search the study list to find studies relevant to your
#    taxon and region. Each study has a numeric STUDY_ID (e.g. 595).
# 4. On the study page, click "Download data" to save the CSV.
#    Files are typically named raw_data_<STUDY_ID>.csv
# 5. Repeat for as many studies as you need.
#
# CITATION REQUIREMENT
# --------------------
# Cite both the BioTime database and each individual study you use:
#   Database: Dornelas et al. (2018) Global Ecology and Biogeography
#             DOI: 10.1111/geb.12729
#   Per-study citations are shown on each study's BioTime page.
#
# PIPELINE OVERVIEW
# -----------------
# Stage 0  — Locate downloaded CSV files
# Stage 1  — Read and DwC-map each study with read_biotime_study()
# Stage 2  — Inspect occurrences
# Stage 3  — Stack with other sources via stack_occurrences()
#
# No catalog harvest, no LLM screening, no API calls.
# All filtering happens after download in Stages 1-2.
# ==============================================================================


# ==============================================================================
# STAGE 0 — Locate your downloaded BioTime CSV files
#
# Option A: point directly at one or more files you have already saved
# Option B: use the interactive file chooser (RStudio only)
# Option C: read all CSVs from a directory
# ==============================================================================

library(TaxaFetch)

# --- Option A: explicit paths (recommended for reproducible scripts) ----------

biotime_paths <- c(
  file.choose()                        # select a BioTime CSV (raw_data_*.csv)
  # file.choose(),                     # add more studies as needed
)

# Check all files exist before proceeding
missing_files <- biotime_paths[!file.exists(biotime_paths)]
if (length(missing_files) > 0L) {
  stop(
    "BioTime file(s) not found:\n",
    paste(" ", missing_files, collapse = "\n"), "\n\n",
    "Download studies from https://biotime.st-andrews.ac.uk/home.php\n",
    "(free registration required)"
  )
}

# --- Option B: interactive file chooser (one file at a time) -----------------
# Suitable for ad hoc exploration in RStudio. Comment out Option A above,
# then uncomment and run this block:
#
# biotime_paths <- character(0L)
# repeat {
#   message("Select a BioTime CSV (Cancel to stop adding files)...")
#   f <- tryCatch(file.choose(), error = function(e) NULL)
#   if (is.null(f) || !nzchar(f)) break
#   biotime_paths <- c(biotime_paths, f)
#   message(sprintf("  Added: %s (%d file(s) total)", basename(f),
#                   length(biotime_paths)))
# }
# if (length(biotime_paths) == 0L) stop("No files selected.")

# --- Option C: read all CSVs from a directory --------------------------------
# Useful when you have downloaded many studies into one folder:
#
# biotime_dir   <- "path/to/biotime_studies"
# biotime_paths <- list.files(biotime_dir, pattern = "raw_data_\\d+\\.csv$",
#                             full.names = TRUE)
# if (length(biotime_paths) == 0L)
#   stop("No raw_data_*.csv files found in: ", biotime_dir)
# message(sprintf("Found %d BioTime CSVs in %s", length(biotime_paths),
#                 biotime_dir))

message(sprintf("Stage 0 complete: %d file(s) located.", length(biotime_paths)))


# ==============================================================================
# STAGE 1 — Read and DwC-map each study
#
# read_biotime_study() handles:
#   - Column renaming to Darwin Core (valid_name → scientificName, etc.)
#   - Type coercion (lat/lon/year/month/day to numeric/integer)
#   - occurrenceStatus ("present" / "absent") from ABUNDANCE and BIOMAS
#   - study_id inference from the filename (raw_data_<id>.csv pattern)
#   - Dropping rows with missing coordinates
#   - biotime_biomass passthrough (BIOMAS, note one-s spelling in source)
#
# study_id is inferred automatically from the filename for standard BioTime
# downloads. Pass study_id explicitly if your files are renamed.
# ==============================================================================

biotime_occ_list <- lapply(biotime_paths, function(path) {
  tryCatch(
    read_biotime_study(local_path = path, verbose = TRUE),
    error = function(e) {
      warning(sprintf("Failed to read '%s': %s", basename(path),
                      conditionMessage(e)), call. = FALSE)
      NULL
    }
  )
})
names(biotime_occ_list) <- basename(biotime_paths)

# Drop any failed reads
n_failed <- sum(vapply(biotime_occ_list, is.null, logical(1L)))
if (n_failed > 0L) warning(sprintf("%d file(s) failed to read.", n_failed))
biotime_occ_list <- Filter(Negate(is.null), biotime_occ_list)

if (length(biotime_occ_list) == 0L) stop("No BioTime files were read successfully.")

message(sprintf("Stage 1 complete: %d study/studies read successfully.",
                length(biotime_occ_list)))


# ==============================================================================
# STAGE 2 — Inspect occurrences
#
# Review each study individually, then optionally filter before stacking.
# Common filters:
#   - occurrenceStatus == "present"  (drop explicit zero records)
#   - year >= from_year              (time window)
#   - scientificName %in% target_taxa  (taxon subset)
# ==============================================================================

for (nm in names(biotime_occ_list)) {
  occ <- biotime_occ_list[[nm]]
  cat(sprintf("\n=== %s ===\n", nm))
  cat(sprintf("  Records      : %d\n", nrow(occ)))
  cat(sprintf("  Present      : %d\n", sum(occ$occurrenceStatus == "present")))
  cat(sprintf("  Absent       : %d\n", sum(occ$occurrenceStatus == "absent")))
  cat(sprintf("  Taxa         : %d unique\n", length(unique(occ$scientificName))))
  cat(sprintf("  Years        : %d - %d\n",
              min(occ$year, na.rm = TRUE), max(occ$year, na.rm = TRUE)))
  cat(sprintf("  Lat range    : %.3f - %.3f\n",
              min(occ$decimalLatitude,  na.rm = TRUE),
              max(occ$decimalLatitude,  na.rm = TRUE)))
  cat(sprintf("  Lon range    : %.3f - %.3f\n",
              min(occ$decimalLongitude, na.rm = TRUE),
              max(occ$decimalLongitude, na.rm = TRUE)))
  cat(sprintf("  datasetID    : %s\n", occ$datasetID[1L]))
  cat("  Taxa:\n")
  print(sort(table(occ$scientificName), decreasing = TRUE))
}

# --- Optional: filter before stacking ----------------------------------------
#
# Filter to present-only records:
# biotime_occ_list <- lapply(biotime_occ_list, function(occ)
#   occ[occ$occurrenceStatus == "present", ])
#
# Filter to a time window:
# from_year <- 1990L
# biotime_occ_list <- lapply(biotime_occ_list, function(occ)
#   occ[!is.na(occ$year) & occ$year >= from_year, ])
#
# Filter to a bounding box:
# bbox <- c(-121.0, -117.0, 33.0, 35.0)   # c(lon_min, lon_max, lat_min, lat_max)
# biotime_occ_list <- lapply(biotime_occ_list, function(occ)
#   occ[!is.na(occ$decimalLongitude) &
#         occ$decimalLongitude >= bbox[1] & occ$decimalLongitude <= bbox[2] &
#         occ$decimalLatitude  >= bbox[3] & occ$decimalLatitude  <= bbox[4], ])
#
# Filter to specific taxa:
# target_taxa <- c("Alloclinus holderi", "Coryphopterus nicholsii")
# biotime_occ_list <- lapply(biotime_occ_list, function(occ)
#   occ[occ$scientificName %in% target_taxa, ])


# ==============================================================================
# STAGE 3 — Stack with other sources
#
# stack_occurrences() accepts any mix of BioTime, DataONE, GBIF, and PDF
# tibbles. It adds point_id and reports record counts per source. Columns
# present in one source but absent in another get NA.
#
# Uncomment the block that applies to your situation.
# ==============================================================================

# --- BioTime only (single study) ---------------------------------------------
biotime_occ <- stack_occurrences(biotime_occ_list)
message(sprintf("Stage 3: %d total BioTime records.", nrow(biotime_occ)))

# --- BioTime + DataONE -------------------------------------------------------
# (assumes dataone_occ exists from Dataone_workflow.R)
# all_occ <- stack_occurrences(list(biotime_occ, dataone_occ))
# message(sprintf("Combined BioTime + DataONE: %d records.", nrow(all_occ)))

# --- BioTime + GBIF ----------------------------------------------------------
# (assumes gbif_occ exists from a fetch_gbif_occurrences() call)
# all_occ <- stack_occurrences(list(biotime_occ, gbif_occ))
# message(sprintf("Combined BioTime + GBIF: %d records.", nrow(all_occ)))

# --- BioTime + DataONE + GBIF + PDF ------------------------------------------
# all_occ <- stack_occurrences(list(biotime_occ, dataone_occ, gbif_occ,
#                                   all_pdf_occ))
# message(sprintf("Combined all sources: %d records.", nrow(all_occ)))

message("biotime_workflow.R complete.")
