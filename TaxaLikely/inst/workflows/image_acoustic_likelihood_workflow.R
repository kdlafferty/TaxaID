# ==============================================================================
# WORKFLOW: IMAGE / ACOUSTIC SCORE-TO-LIKELIHOOD CONVERSION (TaxaLikely)
# ==============================================================================
# Purpose: Convert non-sequence classifier output (iNaturalist CV image scores;
#   BirdNET acoustic confidence) into TaxaAssign-ready likelihoods, using the
#   SAME unreferenced_candidates() + assign_scores() pathway for both --
#   TaxaLikely's own docs already note these are identical (no training step;
#   classifiers are pre-trained; TaxaLikely acts purely as a post-classifier
#   calibration layer). This is unlike the DNA/BLAST path, which needs the
#   full build_sequence_matrix()/DECIPHER/train_likelihood_model() chain.
#
# Audience: someone learning TaxaLikely's non-sequence pathway step by step.
#   Continues directly from TaxaMatch's score_image_workflow.R (IMAGE section)
#   and, once built, TaxaMatch's acoustic ingestion script (ACOUSTIC section).
#
# THIS IS THE SECOND SCRIPT IN A TWO-PACKAGE MINI-CHAIN:
#   TaxaMatch -> TaxaLikely (this script)
# It stops here -- see score_image_workflow.R's header comment for why this
# mini-chain does not continue to TaxaAssign/TaxaFlag.
#
# TWO INDEPENDENT SECTIONS (not a DEBUG_MODE variant switch): unlike
# TaxaFetch/TaxaExpect's VARIANT A/B (mutually exclusive alternatives for the
# SAME goal), image and acoustic are two genuinely different data-type
# checkpoints that can both exist in the same tutorial session. Each section
# below is independently runnable and produces its own likelihood object.
#
# Output: taxalikely_image_likelihoods (Section 1) and
#   taxalikely_acoustic_likelihoods (Section 2) -- see the "Output" block at
#   the end of each section for the full column contract.
# ==============================================================================

# --- Namespaces used in this script (loaded, never attached) ----------------
# TaxaLikely::

# ==============================================================================
# CONFIG
# ==============================================================================
IMAGE_CHECKPOINT_PATH    <- file.path(tempdir(), "tutorial_camtrap_taxamatch_image_match_obj.rds")
ACOUSTIC_CHECKPOINT_PATH <- file.path(tempdir(), "tutorial_sandpiper_taxamatch_acoustic_match_obj.rds")

# ==============================================================================
# SECTION 1: IMAGE (iNaturalist CV) -- LIVE
# ==============================================================================

message("\n=== SECTION 1: IMAGE (iNaturalist CV) ===")

if (!file.exists(IMAGE_CHECKPOINT_PATH)) {
  stop("Checkpoint not found at ", IMAGE_CHECKPOINT_PATH, ". Run TaxaMatch's ",
       "score_image_workflow.R first (in the SAME R session if tempdir() ",
       "has not been reused -- tempdir() is scoped to one R session, exactly ",
       "as documented for the five-package Gadus chain).")
}

taxamatch_image_match_obj <- readRDS(IMAGE_CHECKPOINT_PATH)
message("Loaded TaxaMatch's checkpoint: ", IMAGE_CHECKPOINT_PATH,
        " (", nrow(taxamatch_image_match_obj), " row(s), ",
        length(unique(taxamatch_image_match_obj$observation_id)), " photo(s)).")

# ==============================================================================
# 1a. unreferenced_candidates() -- ADD H2/H3 PLACEHOLDER ROWS
# ==============================================================================
# rank_system supplied explicitly (family, genus, species) rather than relying
# on auto-detection -- TaxaMatch's script already populated exactly these
# three columns in Step 2 for this purpose. include_unreferenced_family = FALSE
# (default): this tutorial does not continue to TaxaAssign/join_priors(), so
# there is no occurrence-based prior to cover unrepresented families; adding
# an unreferenced_family catch-all here would have nothing downstream to
# absorb its posterior mass meaningfully.
# ==============================================================================

message("\n--- Step 1a: unreferenced_candidates() ---")

taxalikely_image_hyp <- TaxaLikely::unreferenced_candidates(
  taxamatch_image_match_obj,
  rank_system = c("family", "genus", "species")
)

message("  hypothesis_type distribution:")
print(table(taxalikely_image_hyp$hypothesis_type))

# ==============================================================================
# 1b. assign_scores() -- similarity_softmax
# ==============================================================================
# score_type = "similarity_softmax", NOT "probability": CONFIRMED BY ACTUALLY
# RUNNING THIS SCRIPT -- score_original (= combined_score from the CV API) is
# an UNBOUNDED raw score, not a 0-1 probability (observed values from ~0.4 up
# to ~3000 across real photos in this tutorial set depending on how
# unambiguous the image was). assign_scores(score_type = "probability")
# actively warns/errors when scores exceed 1 for exactly this reason.
# "similarity_softmax" is the score_type designed for arbitrary-scale
# similarity scores: it exponentiates and ratio-normalizes per observation,
# which is the correct treatment here.
# ==============================================================================

message("\n--- Step 1b: assign_scores(score_type = \"similarity_softmax\") ---")

taxalikely_image_likelihoods <- TaxaLikely::assign_scores(
  taxalikely_image_hyp,
  score_type = "similarity_softmax"
)

# ---- Honesty check: does the winning likelihood match ground truth? --------
.top1 <- taxalikely_image_likelihoods[
  taxalikely_image_likelihoods$hypothesis_type == "specific_candidate",
]
.top1 <- .top1[order(.top1$observation_id, -.top1$score_likelihood), ]
.top1 <- .top1[!duplicated(.top1$observation_id), ]
message(sprintf(
  "  Top-likelihood accuracy: %d/%d correct (%.0f%%).",
  sum(.top1$taxon_name == .top1$true_species),
  nrow(.top1),
  100 * mean(.top1$taxon_name == .top1$true_species)
))

# ---- Explicit checkpoint (not automatic) ------------------------------------
IMAGE_LIKELIHOODS_PATH <- file.path(tempdir(), "tutorial_camtrap_taxalikely_image_likelihoods.rds")
saveRDS(taxalikely_image_likelihoods, IMAGE_LIKELIHOODS_PATH)
message(sprintf("\n  Saved: %s", IMAGE_LIKELIHOODS_PATH))
message(sprintf("  To reuse without re-running this section, paste:\n    taxalikely_image_likelihoods <- readRDS(\"%s\")",
                IMAGE_LIKELIHOODS_PATH))

message("\nSection 1 (IMAGE) complete.")

# ==============================================================================
# Output (Section 1: IMAGE)
# ==============================================================================
# taxalikely_image_likelihoods -- one row per photo (observation_id) x taxon
#   hypothesis (specific_candidate rows from the CV response, plus one
#   unreferenced_species + one unreferenced_genus row per photo):
#
#   observation_id     -- character; photo filename stem
#   taxon_name         -- character; NA for unreferenced_genus rows (both
#                         finest ranks nulled per unreferenced_candidates())
#   taxon_name_rank    -- character
#   hypothesis_type    -- character; "specific_candidate" / "unreferenced_species"
#                         / "unreferenced_genus"
#   score_original     -- numeric; NA for unreferenced_* rows
#   score_likelihood   -- numeric; softmax-normalized point estimate, the
#                         primary column TaxaAssign consumes. CONFIRMED BY
#                         ACTUALLY RUNNING THIS SCRIPT: BOTH "similarity_softmax"
#                         (here) and "probability" (ACOUSTIC section below)
#                         ratio-normalize by the WINNING candidate's own score
#                         within each observation_id (assign_scores.R:
#                         `sc_softmax / max_ss`) -- so the winning row's
#                         score_likelihood is ALWAYS exactly 1.0, regardless of
#                         how confident that win actually was. This is not a
#                         bug; it is what the ecosystem's own docs mean by
#                         "ratio-normalized (/max)". The MEANINGFUL comparison
#                         across observations is therefore "which taxon_name
#                         won" (the honesty check above), not the magnitude of
#                         score_likelihood itself -- score_likelihood is only
#                         informative for the LOSING candidates within one
#                         observation_id.
#   score_likelihood_mean, score_likelihood_sd -- NOT produced by assign_scores()
#                         (those columns come from evaluate_likelihoods(), the
#                         DNA/sequence pathway's Monte-Carlo step; the image/
#                         acoustic pathway has no analogous simulation step)
#   score_method       -- character; "similarity_softmax" for every row
#   family, genus, species -- taxonomy columns carried through from the match
#                         object
#   true_species        -- character; TUTORIAL-ONLY ground-truth label, not
#                         part of the canonical likelihood object contract
#
# Consumer: would be TaxaAssign::join_priors() / compute_posterior(), if this
#   mini-chain continued there (it does not -- see header comment). A real
#   continuation would additionally need TaxaTools::convert_taxonomy_backbone()
#   (NCBI backbone from fill_higher_ranks() vs. whatever backbone the priors
#   use) per score_image_inat()'s own documented downstream note.
# ==============================================================================

# ==============================================================================
# SECTION 2: ACOUSTIC (BirdNET) -- LIVE
# ==============================================================================

message("\n=== SECTION 2: ACOUSTIC (BirdNET) ===")

if (!file.exists(ACOUSTIC_CHECKPOINT_PATH)) {
  stop("Checkpoint not found at ", ACOUSTIC_CHECKPOINT_PATH, ". Run TaxaMatch's ",
       "score_acoustic_workflow.R first (in the SAME R session -- tempdir() ",
       "is scoped to one R session).")
}

taxamatch_acoustic_match_obj <- readRDS(ACOUSTIC_CHECKPOINT_PATH)
message("Loaded TaxaMatch's checkpoint: ", ACOUSTIC_CHECKPOINT_PATH,
        " (", nrow(taxamatch_acoustic_match_obj), " row(s), ",
        length(unique(taxamatch_acoustic_match_obj$observation_id)), " detection window(s)).")

# ==============================================================================
# 2a. unreferenced_candidates()
# ==============================================================================
# Identical call shape to Section 1 (IMAGE) -- rank_system explicit, same
# three columns TaxaMatch's script populated. This is the exact "acoustic and
# image use the same pathway" property TaxaLikely/CLAUDE.md already documents.
# ==============================================================================

message("\n--- Step 2a: unreferenced_candidates() ---")

taxalikely_acoustic_hyp <- TaxaLikely::unreferenced_candidates(
  taxamatch_acoustic_match_obj,
  rank_system = c("family", "genus", "species")
)

message("  hypothesis_type distribution:")
print(table(taxalikely_acoustic_hyp$hypothesis_type))

# ==============================================================================
# 2b. assign_scores() -- probability (NOT similarity_softmax)
# ==============================================================================
# score_type = "probability" here, in deliberate CONTRAST to Section 1's
# "similarity_softmax": CONFIRMED BY ACTUALLY RUNNING THIS SCRIPT -- BirdNET
# confidence (TaxaMatch's `score`/`score_original` column) is ALREADY a
# bounded 0-1 neural-net softmax output, unlike the iNat CV path's unbounded
# combined_score. TaxaLikely::assign_scores()'s own roxygen documents
# `score_type = "probability"` as intended for exactly this case ("Neural-net
# softmax outputs (e.g., BirdNET...)"). Passing "similarity_softmax" here
# would double-apply a softmax transform to an already-softmax-shaped score.
# ==============================================================================

message("\n--- Step 2b: assign_scores(score_type = \"probability\") ---")

taxalikely_acoustic_likelihoods <- TaxaLikely::assign_scores(
  taxalikely_acoustic_hyp,
  score_type = "probability"
)

# ---- Honesty check: does the winning taxon match ground truth? -------------
# CONFIRMED BY ACTUALLY RUNNING THIS SCRIPT: unlike Section 1's clean 100%
# sweep, this is a genuinely mixed, honest result -- real field recordings
# include background noise and real inter-species call confusion (BirdNET's
# top candidate for several Western/Semipalmated Sandpiper detection windows
# is Least Sandpiper or an unrelated species). This is the expected outcome
# for real bioacoustic data, not a bug -- see this script's header comment.
.top1 <- taxalikely_acoustic_likelihoods[
  taxalikely_acoustic_likelihoods$hypothesis_type == "specific_candidate",
]
.top1 <- .top1[order(.top1$observation_id, -.top1$score_likelihood), ]
.top1 <- .top1[!duplicated(.top1$observation_id), ]
message(sprintf(
  "  Top-candidate accuracy across real detection windows: %d/%d correct (%.0f%%).",
  sum(.top1$taxon_name == .top1$true_species),
  nrow(.top1),
  100 * mean(.top1$taxon_name == .top1$true_species)
))
message("  Per-window results (winning taxon vs. known true species):")
print(.top1[, c("observation_id", "true_species", "taxon_name")])

# ---- Explicit checkpoint (not automatic) ------------------------------------
ACOUSTIC_LIKELIHOODS_PATH <- file.path(tempdir(), "tutorial_sandpiper_taxalikely_acoustic_likelihoods.rds")
saveRDS(taxalikely_acoustic_likelihoods, ACOUSTIC_LIKELIHOODS_PATH)
message(sprintf("\n  Saved: %s", ACOUSTIC_LIKELIHOODS_PATH))
message(sprintf("  To reuse without re-running this section, paste:\n    taxalikely_acoustic_likelihoods <- readRDS(\"%s\")",
                ACOUSTIC_LIKELIHOODS_PATH))

message("\nSection 2 (ACOUSTIC) complete.")

# ==============================================================================
# Output (Section 2: ACOUSTIC)
# ==============================================================================
# taxalikely_acoustic_likelihoods -- one row per detection window
#   (observation_id) x taxon hypothesis (BirdNET candidates above
#   MIN_CONFIDENCE, plus one unreferenced_species + one unreferenced_genus row
#   per window):
#
#   observation_id     -- character; "{file_stem}_{start_s}-{end_s}"
#   taxon_name         -- character; NA for unreferenced_genus rows
#   taxon_name_rank    -- character
#   hypothesis_type    -- character; "specific_candidate" / "unreferenced_species"
#                         / "unreferenced_genus"
#   score_original     -- numeric; BirdNET confidence (0-1), NA for
#                         unreferenced_* rows
#   score_likelihood   -- numeric; ratio-normalized point estimate. Same
#                         "winner is always 1.0" property documented in
#                         Section 1's Output block applies here too -- compare
#                         WHICH taxon won, not the magnitude.
#   score_likelihood_mean, score_likelihood_sd -- NOT produced (see Section 1's
#                         Output note; no Monte-Carlo step in this pathway)
#   score_method       -- character; "probability" for every row
#   family, genus, species -- taxonomy columns carried through from the match
#                         object
#   start_s, end_s, source_file, common_name -- carried through from
#                         read_birdnet_output()
#   true_species        -- character; TUTORIAL-ONLY ground-truth label (from
#                         manifest.csv); NOT part of the canonical likelihood
#                         object contract
#
# Consumer: same as Section 1 -- would be TaxaAssign::join_priors() /
#   compute_posterior() if this mini-chain continued there.
# ==============================================================================
