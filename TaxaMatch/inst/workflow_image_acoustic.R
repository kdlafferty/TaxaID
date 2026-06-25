# ==============================================================================
# WORKFLOW: IMAGE AND ACOUSTIC IDENTIFICATION
# TaxaMatch + TaxaLikely  — Session 119 functions
# ==============================================================================
# Purpose: Confirm that the image and acoustic ingestion functions work, then
#   show how to audit coverage for image- and acoustic-based workflows.
#
# Sections:
#   A. score_image_inat()        — submit images to iNat CV API
#   B. read_birdnet_output()     — ingest BirdNET CSVs (both output formats)
#   C. audit_inat_coverage()     — which prior species lack iNat references?
#   D. audit_acoustic_coverage() — which prior species lack BirdNET coverage?
#              with xc_recordings = TRUE to add Xeno-canto recording counts
#
# API access: A and C require an iNaturalist API token (INAT_API_TOKEN env var).
#   D with xc_recordings = TRUE queries Xeno-canto (no key required).
#   B is offline.
#
# Runtime notes: A makes one HTTP POST per image (~0.2s overhead each).
#   C and D (xc) make one GET per species; use small lists for testing.
# ==============================================================================

library(TaxaMatch)
library(TaxaLikely)


# ==============================================================================
# SECTION A: SCORE IMAGES WITH iNATURALIST CV API
# ==============================================================================
# score_image_inat() submits images directly to the iNat CV API and returns a
# canonical match object (observation_id, taxon_name, taxon_name_rank,
# score_original, ...) ready for evaluate_likelihoods().
#
# Requires: INAT_API_TOKEN environment variable
#   Get your token at https://www.inaturalist.org/users/api_token (must be logged in)
#   Add to ~/.Renviron:  INAT_API_TOKEN=your_token_here
# ==============================================================================

# ---- A1. Score a folder of images -------------------------------------------
# Point image_path at a folder of JPEG/PNG images.
# If your images have GPS EXIF data, lat/lng/observed_on are read automatically.
# For images without EXIF (e.g. cropped/edited files), supply them as arguments.

image_dir <- "~/My Drive/Documents2/Lafferty Manuscripts/2 Active/BayesianID_perspective/photos of Western sandpiper"

match_raw <- score_image_inat(
  image_path  = image_dir,
  lat         = 34.10,        # Mugu Lagoon, CA (decimal degrees)
  lng         = -119.07,
  observed_on = "2024-09-01",   # approximate; YYYY-MM or YYYY-MM-DD
  top_n       = 10L,
  recursive   = FALSE
)

cat("Rows returned:", nrow(match_raw), "\n")
cat("Images processed:", length(unique(match_raw$observation_id)), "\n")
print(head(match_raw[, c("observation_id", "taxon_name", "taxon_name_rank",
                          "score_original", "geo_prior_weight", "n_observations")]))

# ---- A2. Inspect score columns ----------------------------------------------
# Scores are in iNat's 0-100 softmax convention (sum ≈ 100 per image).
# vision_score  = CNN output (no location)
# combined_score = vision × geomodel prior (used as score_original)
# geo_prior_weight = combined / vision  (>1 → boosted by location; <1 → suppressed)

cat("\nScore range:\n")
print(summary(match_raw[, c("vision_score", "combined_score", "freq_score",
                              "geo_prior_weight")]))

# ---- A3. Check folder metadata columns --------------------------------------
# Nested folder levels between image_dir and each image are captured as
# folder_1, folder_2, ... — useful for retaining site/date/treatment structure.
folder_cols <- grep("^folder_", names(match_raw), value = TRUE)
if (length(folder_cols) > 0) {
  cat("\nFolder metadata columns:", paste(folder_cols, collapse = ", "), "\n")
  print(unique(match_raw[, folder_cols, drop = FALSE]))
}

# ---- A4. Single image example -----------------------------------------------
# You can also pass a single file or a character vector of paths.

# single_file <- "path/to/one_image.jpg"
# match_one <- score_image_inat(single_file, lat = 34.10, lng = -119.07,
#                                observed_on = "2024-09-15")

# ---- A5. Downstream pipeline note -------------------------------------------
# The iNat CV API returns only the lowest-rank taxon name (species or genus).
# Before joining priors, resolve family-level taxonomy:
#
#   match_std <- TaxaMatch::convert_taxonomy_backbone(match_raw,
#                  rank_system = c("genus", "species"),
#                  target_backbone_id = 11L)   # GBIF
#   taxonomy  <- TaxaTools::fill_higher_ranks(unique(match_std$taxon_name))
#   priors    <- TaxaAssign::join_priors(match_std,
#                  taxaexpect_priors = ...,
#                  expansion_taxonomy = taxonomy)


# ==============================================================================
# SECTION B: INGEST BIRDNET OUTPUT
# ==============================================================================
# BirdNET-Analyzer produces one CSV per recording (CLI format).
# The Gradio web interface and some third-party tools produce a single combined
# CSV with a "File" column. Both are handled automatically.
# ==============================================================================

# ---- B1. CLI format — one CSV per recording (standard) ----------------------
# Each file is named  <recording>.BirdNET.results.csv

BirdNetTable<-read.csv(file.choose())
head(BirdNetTable)
birdnet_cli <- read_birdnet_output(BirdNetTable, min_confidence = 0.1)
cat("\nCLI format — rows:", nrow(birdnet_cli), "\n")
print(birdnet_cli[, c("observation_id", "score", "species", "source_file")])


# ---- B2. Combined format — single CSV with File column (Gradio / web UI) ---
# The Gradio interface exports one combined CSV covering all recordings.
# A "File" column contains the audio file path; observation_id stems are derived
# from the audio filename rather than the CSV filename.

tmp_combined <- tempfile(fileext = ".csv")
write.csv(data.frame(
  "File"            = c("/data/recording1.mp3", "/data/recording1.mp3",
                         "/data/recording2.wav"),
  "Start (s)"       = c(0.0, 0.0, 0.0),
  "End (s)"         = c(3.0, 3.0, 3.0),
  "Scientific name" = c("Turdus migratorius", "Setophaga petechia",
                         "Corvus brachyrhynchos"),
  "Common name"     = c("American Robin", "Yellow Warbler", "American Crow"),
  "Confidence"      = c(0.91, 0.55, 0.83),
  check.names = FALSE, stringsAsFactors = FALSE
), tmp_combined, row.names = FALSE)

birdnet_combined <- read_birdnet_output(tmp_combined, min_confidence = 0.1)
cat("\nCombined format — rows:", nrow(birdnet_combined), "\n")
print(birdnet_combined[, c("observation_id", "score", "species")])
unlink(tmp_combined)

# Confirm observation_ids are derived from audio filenames, not the CSV name:
stopifnot(all(grepl("^recording[12]_", birdnet_combined$observation_id)))
cat("OK — observation_ids derived from audio filenames in File column\n")

# ---- B3. Real data example --------------------------------------------------
# If you have BirdNET output on disk (directory of CLI CSVs):
#
# birdnet_df <- read_birdnet_output("path/to/BirdNET_results/",
#                                   min_confidence = 0.1, top_n = 3L)
#
# Or the Gradio combined CSV:
# birdnet_df <- read_birdnet_output("path/to/BirdNetResults.csv",
#                                   min_confidence = 0.1)


# ==============================================================================
# SECTION C: AUDIT iNATURALIST COVERAGE
# ==============================================================================
# audit_inat_coverage() answers: which species in our prior list are too
# under-observed at iNaturalist to have been included in the CV model?
# Species with < cv_threshold observations are flagged as unreferenced —
# meaning the iNat CV API cannot return them as candidates.
#
# Requires: INAT_API_TOKEN  (free account; read-only; no key tier needed)
# Rate: 0.3s sleep per species — keep test lists short
# ==============================================================================

# Test with a small list of shorebird species plausible at Mugu Lagoon
prior_species_shorebird <- c(
  "Calidris mauri",           # Western Sandpiper      — well-observed
  "Calidris minutilla",       # Least Sandpiper        — well-observed
  "Limosa fedoa",             # Marbled Godwit         — moderate
  "Phalaropus tricolor",      # Wilson's Phalarope     — moderate
  "Calidris canutus"          # Red Knot               — less common
)

cat("\n--- audit_inat_coverage() ---\n")
inat_cov <- audit_inat_coverage(
  species_list  = prior_species_shorebird,
  match_df      = NULL,       # optional: pass match_raw here to annotate in_match_data
  cv_threshold  = 100L,       # iNat CV model estimated to require ~100 research-grade obs
  verbose       = TRUE
)

cat("\niNat coverage census:\n")
print(inat_cov$census)

cat("\nSpecies with insufficient iNat observations (unreferenced):\n")
print(inat_cov$unreferenced)
cat("Count:", length(inat_cov$unreferenced), "\n")

# cv_model_included = TRUE  → species likely in the iNat CV model
# cv_model_included = FALSE → too few observations; CV API cannot return this species
# unreferenced = TRUE       → cv_model_included is FALSE (cannot appear as match candidate)

# ---- C2. With match_df: annotate which prior species actually appeared -------
# Pass your match object to see which species appeared as CV candidates:
#
# inat_cov2 <- audit_inat_coverage(
#   species_list = prior_species_shorebird,
#   match_df     = match_raw,
#   verbose      = TRUE
# )
# print(inat_cov2$census[, c("species", "n_observations", "cv_model_included",
#                              "unreferenced", "in_match_data")])


# ==============================================================================
# SECTION D: AUDIT ACOUSTIC (BIRDNET) COVERAGE + XENO-CANTO COUNTS
# ==============================================================================
# audit_acoustic_coverage() answers: which plausible species at our site
# are absent from the BirdNET classifier's known species list?
#
# With xc_recordings = TRUE, it also queries Xeno-canto for the number of
# reference recordings per species — a useful proxy for acoustic reference quality.
#
# No API key needed for Xeno-canto. Rate: 1s sleep per species.
# ==============================================================================

# BirdNET v2.4 covers ~6,000 species — most common birds are included.
# For this test we use a small subset of the known species list.
birdnet_known_species <- c(
  "Turdus migratorius",
  "Setophaga petechia",
  "Corvus brachyrhynchos",
  "Melospiza melodia",
  "Calidris mauri"       # Western Sandpiper — is it in BirdNET?
)

# Species expected at Mugu Lagoon (prior list)
prior_species_birds <- c(
  "Turdus migratorius",
  "Setophaga petechia",
  "Limosa fedoa",         # Marbled Godwit — not in our mock BirdNET list
  "Selasphorus calliope", # Calliope Hummingbird — not in mock list
  "Calidris mauri"
)

cat("\n--- audit_acoustic_coverage() without Xeno-canto ---\n")
acoustic_cov <- audit_acoustic_coverage(
  plausible_species = prior_species_birds,
  reference_species = birdnet_known_species,
  match_df          = birdnet_cli   # annotate which species appeared in our BirdNET run
)

cat("\nAcoustic coverage census:\n")
print(acoustic_cov$census)
cat("\nSpecies absent from BirdNET classifier:\n")
print(acoustic_cov$unreferenced)

# ---- D2. Add Xeno-canto recording counts ------------------------------------
# xc_recordings = TRUE: adds n_recordings column (how many XC recordings per species)
# Useful to assess whether a species is acoustically well-represented in the wild.
# Runtime: ~1s per species (Xeno-canto rate limit)

cat("\n--- audit_acoustic_coverage() with xc_recordings = TRUE ---\n")
cat("(Queries Xeno-canto API — ~1s per species)\n")

acoustic_cov_xc <- audit_acoustic_coverage(
  plausible_species = prior_species_birds,
  reference_species = birdnet_known_species,
  xc_recordings     = TRUE
)

cat("\nAcoustic + Xeno-canto census:\n")
print(acoustic_cov_xc$census)

# n_recordings: number of Xeno-canto recordings available for each species.
# Species with very few XC recordings may have lower acoustic reference quality
# even when they are included in the BirdNET classifier.

# ---- D3. Combining coverage audits ------------------------------------------
# For a complete acoustic workflow:
#   1. audit_acoustic_coverage()  — which priors lack BirdNET coverage?
#   2. audit_inat_coverage()      — which priors lack iNat image coverage?
#   3. Pass unreferenced lists to TaxaAssign::join_priors() or
#      TaxaLikely::apply_coverage_constraints() to constrain likelihoods.


# ==============================================================================
# SUMMARY: WHAT PASSED
# ==============================================================================

cat("\n==============================\n")
cat("Workflow checks:\n")
cat(" A. score_image_inat()         — ", nrow(match_raw), "rows from",
    length(unique(match_raw$observation_id)), "images\n")
cat(" B1. read_birdnet_output() CLI — ", nrow(birdnet_cli), "rows\n")
cat(" B2. read_birdnet_output() combined (File col) —", nrow(birdnet_combined), "rows\n")
cat(" C. audit_inat_coverage()      — census with", nrow(inat_cov$census), "species\n")
cat(" D. audit_acoustic_coverage()  — census with", nrow(acoustic_cov_xc$census),
    "species;", ncol(acoustic_cov_xc$census), "columns\n")
stopifnot("n_recordings" %in% names(acoustic_cov_xc$census))
cat("    n_recordings column present: OK\n")
cat("==============================\n")
