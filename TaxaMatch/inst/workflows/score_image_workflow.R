# ==============================================================================
# WORKFLOW: SCORE IMAGES VIA iNATURALIST CV (TaxaMatch)
# ==============================================================================
# Purpose: Submit real camera-trap photos to the live iNaturalist computer-
#   vision API and standardize the response into a canonical match object,
#   ready for TaxaLikely's score-to-likelihood conversion.
#
# Audience: someone learning TaxaMatch's IMAGE data-type path step by step.
#   This is a SEPARATE tutorial chain from the five-package Gadus/GBIF-
#   occurrence chain (fetch_occurrences_workflow.R etc.) -- image
#   classification has no natural connection to that chain's data, so this
#   script starts its own real-data story instead of bootstrapping something
#   synthetic on top of it.
#
# THIS SCRIPT IS THE FIRST OF A TWO-PACKAGE MINI-CHAIN:
#   TaxaMatch (this script) -> TaxaLikely (image_acoustic_likelihood_workflow.R)
# It stops at TaxaLikely -- it does not continue to TaxaAssign/TaxaFlag. Item 4
# of ecosystem_docs/REENTRY_PROMPT_session123_layer1_workflows.md scoped this
# as "produce a real likelihood object", which is TaxaAssign's actual input;
# building a full TaxaAssign run on top of these species would need real
# occurrence-based priors for them, which is a separate task.
#
# NO SYNTHETIC DATA, AND OWNED BY THE USER: 6 real Bushnell trail-camera
# photos (Central California coastal scrub habitat, 34.41 N / -119.86 W) of
# 5 mammal species across 4 families -- Bobcat (Lynx rufus, Felidae), Coyote
# (Canis latrans, Canidae), Brush Rabbit (Sylvilagus bachmani, Leporidae),
# Western Spotted Skunk (Spilogale gracilis, Mephitidae), and Striped Skunk
# (Mephitis mephitis, Mephitidae; 2 photos). DELIBERATE DESIGN CHOICE (per
# discussion with the user): a DIVERSITY OF TAXA, not many replicate photos
# of one species or a single confusable-congener pair -- consistent with how
# TaxaMatch's BLAST/sequence field test (Session 115) used a handful of real
# queries across different taxa to demonstrate the PIPELINE, not a rigorous
# CV-accuracy calibration study (that would need many replicate photos per
# species, a different and separable question).
#
# These photos ARE bundled in inst/extdata/example_images/camera_trap_photos/
# (unlike an earlier iteration of this script, which used bird photos of
# uncertain third-party licensing from eBird/Macaulay Library screenshots --
# replaced after the user pointed out those weren't photos they had rights to
# redistribute). These camera-trap photos are the user's own.
#
# Output: taxamatch_image_match_obj -- see "Output" block at the end of this
#   file for the full column contract passed to TaxaLikely.
# ==============================================================================

# --- Namespaces used in this script (loaded, never attached) ----------------
# TaxaMatch::, TaxaTools::, dplyr::

# ==============================================================================
# CONFIG
# ==============================================================================
# Parameters are grouped here so this script's body can become a wrapper
# function's implementation with minimal changes -- each CONFIG value maps to
# a future function argument.

# DEBUG_MODE = TRUE  -> live-call the iNaturalist CV API on the bundled
#                       camera-trap photo set described above.
# DEBUG_MODE = FALSE -> plug in your own photo directory (see the
#                       "SWAP IN YOUR OWN DATA" block below)
DEBUG_MODE <- TRUE

# top_n for score_image_inat(): the full candidate list is needed for
# assign_scores()'s softmax normalization downstream. A top_n = 1 result
# would collapse to the "single-H1 caveat" documented in TaxaLikely's
# assign_scores() -- H2/H3 anchoring loses all discriminating power when only
# the winning candidate is known.
TOP_N <- 5L

# Real camera location (Central California coastal scrub habitat) --
# CONFIRMED BY ACTUALLY RUNNING THIS SCRIPT: supplying the true lat/lng
# measurably changed results (iNat's combined_score blends vision confidence
# with local occurrence frequency) -- 2 of 6 photos flipped from wrong to
# correct once the real location was supplied instead of leaving lat/lng NULL
# (which would fall back to EXIF, absent on these trail-camera files, or no
# geographic prior at all).
SITE_LAT <- 34.41
SITE_LNG <- -119.86

if (DEBUG_MODE) {

  # ---- Tutorial example: real camera-trap photos, bundled with the package --
  .photo_dir <- system.file(
    "extdata", "example_images", "camera_trap_photos",
    package = "TaxaMatch"
  )

  if (!nzchar(.photo_dir) || !dir.exists(.photo_dir)) {
    stop("DEBUG_MODE = TRUE but the bundled camera-trap photo directory was ",
         "not found. Reinstall TaxaMatch (devtools::install()) so ",
         "inst/extdata/example_images/camera_trap_photos/ ships with the ",
         "installed package, or point DEBUG_MODE <- FALSE at your own photos.")
  }

  photo_files <- list.files(.photo_dir, pattern = "\\.JPG$", full.names = TRUE)

  message(sprintf(
    "DEBUG_MODE = TRUE -- found %d bundled camera-trap photo(s) in %s.",
    length(photo_files), .photo_dir
  ))

  # true_species is added purely for THIS TUTORIAL's own honesty check below
  # (comparing the CV model's top candidate against known ground truth) -- it
  # is not part of the canonical match object contract and is dropped before
  # any downstream use beyond this tutorial. Confirmed directly by the user
  # (filenames alone are ambiguous at species level for rabbit/spotted skunk
  # -- several candidate species exist in North America).
  TRUE_SPECIES <- c(
    bobcat        = "Lynx rufus",
    coyote        = "Canis latrans",
    rabbit        = "Sylvilagus bachmani",
    spottedskunk  = "Spilogale gracilis",
    stripedskunk  = "Mephitis mephitis",
    stripedskunk2 = "Mephitis mephitis"
  )

} else {

  # ==========================================================================
  # >>> SWAP IN YOUR OWN DATA <<<
  # ==========================================================================
  # Replace the block above with your own photo directory:
  #
  #   photo_files <- list.files("path/to/your/photos", full.names = TRUE)
  #   TRUE_SPECIES <- c(
  #     photo1_stem = "Genus species1",
  #     photo2_stem = "Genus species2",
  #     ...
  #   )
  #   SITE_LAT <- your_real_latitude
  #   SITE_LNG <- your_real_longitude
  #
  #   (TRUE_SPECIES only exists for the honesty check below -- for a real,
  #   unknown-identity survey, skip it and just call score_image_inat() on
  #   your photo directory directly)
  #
  # Set DEBUG_MODE <- FALSE above and fill in the values here.
  # ==========================================================================
  stop("DEBUG_MODE is FALSE but no real photo directory has been supplied. ",
       "Edit the 'SWAP IN YOUR OWN DATA' block in this script.")
}

# Output location for checkpoint files (see explicit-checkpoint pattern below)
OUT_DIR    <- tempdir()
OUT_PREFIX <- "tutorial_camtrap"

# ==============================================================================
# 1.  SCORE IMAGES -- LIVE iNATURALIST CV API CALL
# ==============================================================================
# One real HTTP POST per photo (rate-limited internally at 0.2s/image).
# Requires INAT_API_TOKEN in the environment (~/.Renviron) -- generate one at
# https://www.inaturalist.org/users/api_token.
#
# KNOWN FOOTGUN (found live-testing this script): the token is a short-lived
# JWT (this session's token had already expired after ~1 week) -- a 401
# response means the token needs regenerating, NOT a code bug.
# ==============================================================================

message("\n--- Step 1: Scoring images via live iNaturalist CV API ---")
message("  Requires INAT_API_TOKEN (~/.Renviron) -- 401 means the token has ",
        "expired, not a code bug; regenerate at ",
        "https://www.inaturalist.org/users/api_token.")

taxamatch_image_match_obj <- TaxaMatch::score_image_inat(
  photo_files, lat = SITE_LAT, lng = SITE_LNG, top_n = TOP_N
)
taxamatch_image_match_obj$true_species <-
  TRUE_SPECIES[taxamatch_image_match_obj$observation_id]

message(sprintf(
  "  Scored %d photo(s) (%d candidate row(s) total across top_n = %d).",
  length(unique(taxamatch_image_match_obj$observation_id)),
  nrow(taxamatch_image_match_obj), TOP_N
))

# ---- Honesty check: does the CV model's top candidate match ground truth? --
# This is a real accuracy check on real data, not a synthetic sanity check --
# useful to report even though it isn't part of the match object itself.
# CONFIRMED BY ACTUALLY RUNNING THIS SCRIPT: 5/6 correct with the real site
# lat/lng supplied. The one miss (coyote.JPG) is a genuinely interesting real
# failure: BirdNET's cousin problem here is name/geo-prior collision -- the
# top candidate was Baccharis pilularis ("coyote brush"), a locally abundant
# PLANT whose common name shares the word "coyote", not a taxonomic near-miss.
.top1 <- taxamatch_image_match_obj[order(
  taxamatch_image_match_obj$observation_id, -taxamatch_image_match_obj$combined_score
), ]
.top1 <- .top1[!duplicated(.top1$observation_id), ]
message(sprintf(
  "  Top-1 CV accuracy on this photo set: %d/%d correct (%.0f%%).",
  sum(.top1$taxon_name == .top1$true_species),
  nrow(.top1),
  100 * mean(.top1$taxon_name == .top1$true_species)
))

# ==============================================================================
# 2.  FILL FAMILY/GENUS -- REQUIRED BEFORE unreferenced_candidates()
# ==============================================================================
# score_image_inat()'s own docs note `family` is not populated (not present in
# the CV API response) -- only `genus` and the full binomial `taxon_name` are.
# TaxaLikely::unreferenced_candidates() needs >= 2 populated rank columns to
# auto-detect rank_system and build H2 (unreferenced species)/H3 (unreferenced
# genus) placeholder rows, so `family` must be filled in explicitly first.
#
# CONFIRMED BY ACTUALLY RUNNING THIS SCRIPT: fill_higher_ranks() returns
# taxon_name + genus + family only (per its own roxygen @return) -- it does
# NOT return a `species` column, and unreferenced_candidates() needs the
# FINEST rank column (here, "species") to null out for H2. The ecosystem
# convention for this (see fill_higher_ranks()'s own @examples, which renames
# taxon_name -> species for a sibling function) is that the "species" column
# holds the FULL BINOMIAL, same value as taxon_name -- not the epithet alone.
#
# This photo set spans 4 distinct families (Felidae, Canidae, Leporidae,
# Mephitidae) -- a much more taxonomically diverse test of fill_higher_ranks()
# than a single-family confusable-congener set would be.
# ==============================================================================

message("\n--- Step 2: Filling family/genus via TaxaTools::fill_higher_ranks() ---")

.higher <- TaxaTools::fill_higher_ranks(
  unique(taxamatch_image_match_obj$taxon_name),
  verbose = FALSE
)

taxamatch_image_match_obj <- dplyr::left_join(
  taxamatch_image_match_obj,
  dplyr::select(.higher, taxon_name, family),
  by = "taxon_name"
)
taxamatch_image_match_obj$species <- taxamatch_image_match_obj$taxon_name

message(sprintf("  family resolved for %d/%d unique taxon_name value(s): %s",
                sum(!is.na(.higher$family)), nrow(.higher),
                paste(sort(unique(.higher$family)), collapse = ", ")))

# ---- Explicit checkpoint (not automatic) ------------------------------------
# Save now so a future session (or TaxaLikely's script) can skip Steps 1-2 by
# pasting the readRDS() line below -- no file.exists()-gated auto-reload; you
# decide when to reuse this.
taxamatch_image_match_obj_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_taxamatch_image_match_obj.rds"))
saveRDS(taxamatch_image_match_obj, taxamatch_image_match_obj_path)
message(sprintf("\n  Saved: %s", taxamatch_image_match_obj_path))
message(sprintf("  To reuse without re-querying the CV API, paste:\n    taxamatch_image_match_obj <- readRDS(\"%s\")",
                taxamatch_image_match_obj_path))

message("\nWorkflow complete. Continue with TaxaLikely's ",
        "image_acoustic_likelihood_workflow.R (IMAGE section).")

# ==============================================================================
# Output
# ==============================================================================
# taxamatch_image_match_obj -- one row per photo (observation_id) x candidate
#   species (up to top_n rows per photo), REAL live iNaturalist CV output for
#   5 mammal species across 4 families from real camera-trap photos:
#
#   observation_id     -- character; filename stem, one per photo
#   taxon_name         -- character; candidate species binomial
#   taxon_name_rank    -- character; "species" for every row (CV model output)
#   score_original     -- numeric; = combined_score (see below); UNBOUNDED,
#                         NOT a 0-100 percentage despite superficially looking
#                         like one for most rows. Pass score_type =
#                         "similarity_softmax" (NOT "probability", which
#                         errors/warns above 1.0) to TaxaLikely::assign_scores().
#   genus              -- character; from the CV response (or filled)
#   family             -- character; ADDED in Step 2, was absent from
#                         score_image_inat()'s raw output
#   species            -- character; ADDED in Step 2, = taxon_name (full
#                         binomial, ecosystem convention -- see Step 2 comment)
#   common_name, iconic_taxon_name, taxon_id, n_observations, vision_score,
#   combined_score, freq_score, geo_prior_weight, lat, lng, observed_on --
#                         see score_image_inat()'s own documentation
#   true_species        -- character; TUTORIAL-ONLY ground-truth label for the
#                         honesty check above; NOT part of the canonical match
#                         object contract, harmless extra column for
#                         downstream (unreferenced_candidates()/assign_scores()
#                         ignore unrecognized columns)
#
# Consumer: TaxaLikely::image_acoustic_likelihood_workflow.R (IMAGE section) --
#   calls unreferenced_candidates(rank_system = c("family","genus","species"))
#   then assign_scores(score_type = "similarity_softmax").
# ==============================================================================
