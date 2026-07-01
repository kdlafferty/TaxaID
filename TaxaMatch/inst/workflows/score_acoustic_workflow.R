# ==============================================================================
# WORKFLOW: SCORE RECORDINGS VIA BirdNET (TaxaMatch)
# ==============================================================================
# Purpose: Ingest real BirdNET-Analyzer CSV output (produced by actually
#   running the BirdNET acoustic classifier on real recordings) and
#   standardize it into a canonical match object, ready for TaxaLikely's
#   score-to-likelihood conversion.
#
# Audience: someone learning TaxaMatch's ACOUSTIC data-type path step by step.
#   Sibling script to score_image_workflow.R -- same two-package mini-chain
#   shape (TaxaMatch -> TaxaLikely), different data type. See that script's
#   header comment for why this does not continue to TaxaAssign/TaxaFlag.
#
# WHERE THE REAL BirdNET CSVs CAME FROM: "we won't work directly from sound
# files, instead we will use BirdNET to do the matching for us" -- this
# ecosystem does not run classifiers itself (see TaxaMatch/CLAUDE.md's Design
# notes for non-sequence data types: "no model fitting or classification
# happens in TaxaMatch"). A companion Python script,
# sources/birdnet_csv_export.py (in the same project folder as the photos
# used by score_image_workflow.R), downloads real Xeno-canto recordings for
# three confusable Calidris sandpipers and runs the real BirdNET model
# (birdnetlib) to produce one CLI-format CSV per recording -- exactly the
# `recording.BirdNET.results.csv` shape read_birdnet_output() expects. This R
# script does not re-run BirdNET; it ingests CSVs that already exist on disk.
#
# NO SYNTHETIC DATA: every row comes from a REAL BirdNET model run on REAL
# field recordings of three genuinely confusable congeners -- Western
# Sandpiper (Calidris mauri), Least Sandpiper (Calidris minutilla), and
# Semipalmated Sandpiper (Calidris pusilla). Two of these (mauri, pusilla)
# are the same two species used in score_image_workflow.R -- a deliberate
# choice, so a reader can compare how the SAME species pair discriminates
# under image vs. acoustic classification.
#
# CONFIRMED BY ACTUALLY RUNNING THIS SCRIPT: this is NOT a clean-sweep result
# like the image path. Real field recordings include background noise and
# genuinely confusable calls -- BirdNET's top candidate is wrong for several
# detection windows (most often confusing mauri/pusilla for minutilla, or for
# unrelated background species like Killdeer). This is the expected, honest
# outcome for real bioacoustic data, not a bug -- and is exactly the kind of
# self-vs-nonself confusion the original birdnet_calidris_selftest.py script
# (which this workflow's CSV-export companion was adapted from) was written
# to explore.
#
# Output: taxamatch_acoustic_match_obj -- see "Output" block at the end of
#   this file for the full column contract passed to TaxaLikely.
# ==============================================================================

# --- Namespaces used in this script (loaded, never attached) ----------------
# TaxaMatch::, TaxaTools::, dplyr::

# ==============================================================================
# CONFIG
# ==============================================================================

# DEBUG_MODE = TRUE  -> ingest the real BirdNET CSV output described above.
# DEBUG_MODE = FALSE -> plug in your own BirdNET CSV directory (see the
#                       "SWAP IN YOUR OWN DATA" block below)
DEBUG_MODE <- TRUE

# min_confidence for read_birdnet_output(): BirdNET's OWN default threshold
# (per read_birdnet_output()'s roxygen docs) -- not this package's arbitrary
# choice. Detections below this are typically noise, not missed calls.
MIN_CONFIDENCE <- 0.1

if (DEBUG_MODE) {

  # ---- Tutorial example: real BirdNET output for 3 confusable Calidris ------
  # Same licensing/privacy reasoning as score_image_workflow.R: this points to
  # an absolute path in the user's own project folder rather than
  # package-bundled inst/extdata data. Unlike the photos, these specific CSVs
  # (BirdNET's own numeric output) carry no photographer-licensing concern --
  # but they are still process artifacts of a real study, not maintained
  # tutorial fixtures, so they are not bundled either.
  .csv_dir <- "/Users/lafferty/My Drive/Documents2/Lafferty Manuscripts/2 Active/BayesianID_perspective/sources/birdnet_csv_output"
  .manifest_path <- file.path(.csv_dir, "manifest.csv")

  if (!dir.exists(.csv_dir) || !file.exists(.manifest_path)) {
    stop("DEBUG_MODE = TRUE but the tutorial BirdNET CSV directory/manifest ",
         "was not found at:\n  ", .csv_dir, "\n",
         "Run sources/birdnet_csv_export.py first (requires ",
         "pip install birdnetlib requests and an XC_API_KEY -- see that ",
         "script's header for details), or point DEBUG_MODE <- FALSE at ",
         "your own BirdNET-Analyzer CSV output.")
  }

  # manifest.csv (written by birdnet_csv_export.py) maps each CSV filename to
  # the recording's KNOWN true species -- needed only for THIS TUTORIAL's own
  # honesty check below, not part of the canonical match object contract.
  .manifest <- utils::read.csv(.manifest_path, stringsAsFactors = FALSE)
  message(sprintf("DEBUG_MODE = TRUE -- found %d real BirdNET CSV(s) in %s.",
                  nrow(.manifest), .csv_dir))

} else {

  # ==========================================================================
  # >>> SWAP IN YOUR OWN DATA <<<
  # ==========================================================================
  # Replace the block above with your own BirdNET-Analyzer CSV output:
  #
  #   .csv_dir <- "path/to/your/birdnet_results_directory"
  #     (one recording.BirdNET.results.csv per recording -- see
  #     read_birdnet_output()'s own documentation for the combined-CSV /
  #     Gradio-export alternative format)
  #
  #   .manifest <- NULL
  #     (the true_species honesty check below only applies when ground truth
  #     is known, e.g. a validation recording set with known species; skip it
  #     entirely for a real, unknown-identity acoustic survey)
  #
  # Set DEBUG_MODE <- FALSE above and fill in the values here.
  # ==========================================================================
  stop("DEBUG_MODE is FALSE but no real BirdNET CSV directory has been ",
       "supplied. Edit the 'SWAP IN YOUR OWN DATA' block in this script.")
}

# Output location for checkpoint files (see explicit-checkpoint pattern below)
OUT_DIR    <- tempdir()
OUT_PREFIX <- "tutorial_sandpiper"

# ==============================================================================
# 1.  READ BirdNET OUTPUT
# ==============================================================================
# read_birdnet_output() already handles the Session 88 empty-CSV edge case
# gracefully (a recording with zero detections above BirdNET's internal
# threshold produces an informational message, not an error) -- CONFIRMED BY
# ACTUALLY RUNNING THIS SCRIPT: one of the 9 real recordings in this tutorial
# set (a Semipalmated Sandpiper clip) triggered exactly this path.
# ==============================================================================

message("\n--- Step 1: Reading real BirdNET-Analyzer CSV output ---")

taxamatch_acoustic_match_obj <- TaxaMatch::read_birdnet_output(
  .csv_dir,
  min_confidence = MIN_CONFIDENCE
)

message(sprintf(
  "  Read %d detection row(s) across %d detection window(s) (observation_id).",
  nrow(taxamatch_acoustic_match_obj),
  length(unique(taxamatch_acoustic_match_obj$observation_id))
))

# ==============================================================================
# 2.  DERIVE taxon_name/taxon_name_rank + FILL family
# ==============================================================================
# CONFIRMED BY ACTUALLY RUNNING THIS SCRIPT: read_birdnet_output()'s own
# output has `species` (full binomial) and `genus`, but NOT `taxon_name` /
# `taxon_name_rank` -- the two columns TaxaLikely::unreferenced_candidates()
# actually requires. This is the SAME cross-script contract gap already
# documented for TaxaFetch's output in the five-package Gadus chain (see
# LAYER1_WORKFLOWS.md Bug #12) -- derive via TaxaTools::create_taxon_names()
# rather than assuming the upstream reader's shape already matches.
#
# `family` is filled the same way as score_image_workflow.R's Step 2 (BirdNET
# output has no family column either) -- reusing fill_higher_ranks() gives
# both data-type paths an identical taxonomy-completion step, worth comparing
# directly.
# ==============================================================================

message("\n--- Step 2: Deriving taxon_name + filling family ---")

taxamatch_acoustic_match_obj <- TaxaTools::create_taxon_names(
  taxamatch_acoustic_match_obj,
  rank_system = c("genus", "species")
)

.higher <- TaxaTools::fill_higher_ranks(
  unique(taxamatch_acoustic_match_obj$taxon_name),
  verbose = FALSE
)
taxamatch_acoustic_match_obj <- dplyr::left_join(
  taxamatch_acoustic_match_obj,
  dplyr::select(.higher, taxon_name, family),
  by = "taxon_name"
)

# score_original: unreferenced_candidates()/assign_scores() look for this
# name specifically (BirdNET's own reader names it just "score").
taxamatch_acoustic_match_obj$score_original <- taxamatch_acoustic_match_obj$score

# true_species (tutorial-only honesty check, see manifest note above) --
# joined via source_file, since one CSV/recording can produce many
# observation_id detection windows.
taxamatch_acoustic_match_obj <- dplyr::left_join(
  taxamatch_acoustic_match_obj,
  .manifest,
  by = c("source_file" = "csv_file")
)

message(sprintf("  family resolved for %d/%d unique taxon_name value(s).",
                sum(!is.na(.higher$family)), nrow(.higher)))

# ---- Explicit checkpoint (not automatic) ------------------------------------
taxamatch_acoustic_match_obj_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_taxamatch_acoustic_match_obj.rds"))
saveRDS(taxamatch_acoustic_match_obj, taxamatch_acoustic_match_obj_path)
message(sprintf("\n  Saved: %s", taxamatch_acoustic_match_obj_path))
message(sprintf("  To reuse without re-reading the CSVs, paste:\n    taxamatch_acoustic_match_obj <- readRDS(\"%s\")",
                taxamatch_acoustic_match_obj_path))

message("\nWorkflow complete. Continue with TaxaLikely's ",
        "image_acoustic_likelihood_workflow.R (ACOUSTIC section).")

# ==============================================================================
# Output
# ==============================================================================
# taxamatch_acoustic_match_obj -- one row per detection window (observation_id,
#   e.g. "Calidris_mauri_XC546122_15-18") x candidate species BirdNET reported
#   above MIN_CONFIDENCE for that window:
#
#   observation_id      -- character; "{file_stem}_{start_s}-{end_s}"
#   score, score_original -- numeric; BirdNET confidence, ALREADY 0-1 bounded
#                          (unlike the image path's unbounded combined_score --
#                          pass score_type = "probability", NOT
#                          "similarity_softmax", to TaxaLikely::assign_scores())
#   species             -- character; full binomial (from BirdNET's
#                          "Scientific name" column)
#   genus               -- character; first word of species
#   taxon_name          -- character; ADDED in Step 2 (= species)
#   taxon_name_rank     -- character; ADDED in Step 2 ("species" for every row)
#   family              -- character; ADDED in Step 2, was absent from
#                          read_birdnet_output()'s raw output
#   common_name, start_s, end_s, source_file -- see read_birdnet_output()'s
#                          own documentation
#   true_species         -- character; TUTORIAL-ONLY ground-truth label (from
#                          manifest.csv, joined by source_file) for the
#                          honesty check in TaxaLikely's script; NOT part of
#                          the canonical match object contract
#
# Consumer: TaxaLikely::image_acoustic_likelihood_workflow.R (ACOUSTIC
#   section) -- calls unreferenced_candidates(rank_system =
#   c("family","genus","species")) then assign_scores(score_type = "probability").
# ==============================================================================
