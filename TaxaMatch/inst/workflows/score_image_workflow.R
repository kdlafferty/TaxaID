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
# NO SYNTHETIC DATA, AND OWNED BY THE USER: 52 real Bushnell trail-camera
# photos (Central California coastal scrub habitat, 34.41 N / -119.86 W) of
# 8 mammal species across 7 families, organized into per-species subfolders
# (folder name = common name; see FOLDER_TO_SPECIES below) -- Bobcat (Lynx
# rufus, Felidae, 8 photos), Coyote (Canis latrans, Canidae, 4), Brush Rabbit
# (Sylvilagus bachmani, Leporidae, 6), Western Spotted Skunk (Spilogale
# gracilis, Mephitidae, 6), Striped Skunk (Mephitis mephitis, Mephitidae, 7),
# Raccoon (Procyon lotor, Procyonidae, 10), California Ground Squirrel
# (Otospermophilus beecheyi, Sciuridae, 5), and Virginia Opossum (Didelphis
# virginiana, Didelphidae, 6). EXPANDED from an original 6-photo/5-species
# diversity-only set specifically to get enough replicate photos per species
# to move past a single-flip small-n result on whether
# TaxaLikely::correct_training_bias() is safe to enable by default for the
# image pathway (see ecosystem_docs/REENTRY_PROMPT_session128... and
# TaxaAssign/inst/workflows/camera_trap_posterior_workflow.R, which first
# raised this on n=6).
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
# the winning candidate is known. Bumped from 5 to 8 (safety margin): with
# TARGET_ICONIC_TAXA filtering below now removing off-scope candidates
# (plants, birds) from each photo's top_n, a smaller top_n risks leaving too
# few or zero real mammal candidates for photos where the CV model's top
# guesses are unusually noisy.
TOP_N <- 8L

# iNaturalist's CV model returns candidates from ANY iconic taxon, not just
# the study's actual domain -- confirmed by real output on this photo set:
# "coyote brush" (Baccharis pilularis, a plant) and "Longleaf Wattle"
# (Acacia longifolia, a plant) both appeared as top candidates for
# coyote.JPG (name/geo-prior collision with the word "coyote"), and a
# screech owl (Megascops kennicottii, a bird) appeared for rabbit.JPG.
# score_image_inat()'s raw output already carries iconic_taxon_name (iNat's
# own broad clade label) -- no external taxonomic-scope lookup needed.
# Filtering to the study's actual domain BEFORE unreferenced_candidates()/
# assign_scores() softmax-normalizes lets real candidates absorb the
# probability mass currently wasted on biologically impossible ones, rather
# than just flagging them for review after the fact (TaxaFlag's
# "taxonomic scope" review dimension catches this too, but only after the
# likelihood/posterior math has already run on the polluted candidate set).
TARGET_ICONIC_TAXA <- "Mammalia"

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

  # Photos are now organized into per-species subfolders (common name ==
  # folder name) rather than a flat file list -- recursive = TRUE scans all
  # of them. Just for the pre-flight count message here; the actual call to
  # score_image_inat() below passes .photo_dir directly (not this vector) so
  # it can derive its own folder_1 column from the same directory structure.
  photo_files <- list.files(.photo_dir, pattern = "\\.JPG$", full.names = TRUE,
                            recursive = TRUE, ignore.case = TRUE)

  message(sprintf(
    "DEBUG_MODE = TRUE -- found %d bundled camera-trap photo(s) in %s.",
    length(photo_files), .photo_dir
  ))

  # true_species is added purely for THIS TUTORIAL's own honesty check below
  # (comparing the CV model's top candidate against known ground truth) -- it
  # is not part of the canonical match object contract and is dropped before
  # any downstream use beyond this tutorial. Derived from folder_1 (each
  # photo's immediate subfolder = common name) rather than a per-filename
  # lookup, now that photos are organized into per-species subfolders rather
  # than a flat file list with descriptive names -- filenames alone are
  # camera-generated sequence numbers, not species identifiers.
  #
  # CONFIRM: "ground squirrel" is assumed to be the California ground
  # squirrel (Otospermophilus beecheyi) -- by far the expected species for
  # this real site (coastal Santa Barbara County), but not verified against
  # the actual photos. Correct this line if a different species is pictured.
  FOLDER_TO_SPECIES <- c(
    bobcat             = "Lynx rufus",
    coyote             = "Canis latrans",
    rabbit             = "Sylvilagus bachmani",
    spottedskunk       = "Spilogale gracilis",
    stripedskunk       = "Mephitis mephitis",
    raccoon            = "Procyon lotor",
    "ground squirrel"  = "Otospermophilus beecheyi",
    Opossum            = "Didelphis virginiana"
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
  .photo_dir, lat = SITE_LAT, lng = SITE_LNG, top_n = TOP_N, recursive = TRUE
)
taxamatch_image_match_obj$true_species <-
  FOLDER_TO_SPECIES[taxamatch_image_match_obj$folder_1]

message(sprintf(
  "  Scored %d photo(s) (%d candidate row(s) total across top_n = %d).",
  length(unique(taxamatch_image_match_obj$observation_id)),
  nrow(taxamatch_image_match_obj), TOP_N
))

# ---- Taxonomic-scope filter -------------------------------------------------
# Drop candidates outside TARGET_ICONIC_TAXA before any downstream step gets
# a chance to assign them probability mass (see TARGET_ICONIC_TAXA's own
# comment above for why -- real off-scope candidates observed on this exact
# photo set: two plants for coyote.JPG, a screech owl for rabbit.JPG).
.obs_before_scope <- unique(taxamatch_image_match_obj$observation_id)
.n_before_scope    <- nrow(taxamatch_image_match_obj)
.off_scope <- taxamatch_image_match_obj[
  !is.na(taxamatch_image_match_obj$iconic_taxon_name) &
    taxamatch_image_match_obj$iconic_taxon_name != TARGET_ICONIC_TAXA,
]
if (nrow(.off_scope) > 0L) {
  message(sprintf(
    "  Dropping %d/%d candidate row(s) outside TARGET_ICONIC_TAXA = \"%s\": %s",
    nrow(.off_scope), .n_before_scope, TARGET_ICONIC_TAXA,
    paste(sort(unique(.off_scope$iconic_taxon_name)), collapse = ", ")
  ))
  print(.off_scope[, c("observation_id", "taxon_name", "iconic_taxon_name", "combined_score")])
}
taxamatch_image_match_obj <- taxamatch_image_match_obj[
  is.na(taxamatch_image_match_obj$iconic_taxon_name) |
    taxamatch_image_match_obj$iconic_taxon_name == TARGET_ICONIC_TAXA,
]

# Guard: a photo losing ALL its candidates to scope filtering would silently
# vanish from every downstream step rather than error -- surface it loudly
# instead so it can be inspected (e.g. top_n may need raising further, or
# the photo may genuinely have no plausible in-scope CV candidate at all).
.orphaned <- setdiff(.obs_before_scope, unique(taxamatch_image_match_obj$observation_id))
if (length(.orphaned) > 0L) {
  warning(sprintf(
    "score_image_workflow: %d photo(s) lost ALL candidates to the TARGET_ICONIC_TAXA filter: %s. Raise TOP_N or inspect these photos directly.",
    length(.orphaned), paste(.orphaned, collapse = ", ")
  ), call. = FALSE)
}

# ---- Honesty check: does the CV model's top candidate match ground truth? --
# This is a real accuracy check on real data, not a synthetic sanity check --
# useful to report even though it isn't part of the match object itself.
# PRIOR RESULT (original 6-photo/5-species set, Session 124): 5/6 correct
# with the real site lat/lng supplied. The one miss (coyote.JPG) was a
# genuinely interesting real failure: name/geo-prior collision -- the top
# candidate was Baccharis pilularis ("coyote brush"), a locally abundant
# PLANT whose common name shares the word "coyote", not a taxonomic
# near-miss. Not yet re-confirmed on the expanded 52-photo/8-species set --
# the number below reflects whatever this run actually returns.
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
# This photo set spans 7 distinct families (Felidae, Canidae, Leporidae,
# Mephitidae, Procyonidae, Sciuridae, Didelphidae) -- a much more
# taxonomically diverse test of fill_higher_ranks() than a single-family
# confusable-congener set would be.
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
#   8 mammal species across 7 families from real camera-trap photos:
#
#   observation_id     -- character; filename stem, one per photo
#   folder_1            -- character; immediate subfolder name (common name);
#                         used above to derive true_species via
#                         FOLDER_TO_SPECIES, since filenames are camera-
#                         generated sequence numbers, not species identifiers
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
