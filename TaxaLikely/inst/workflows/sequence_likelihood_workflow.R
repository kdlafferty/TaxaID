# ==============================================================================
# WORKFLOW: SEQUENCE (BLAST) SCORE-TO-LIKELIHOOD CONVERSION (TaxaLikely)
# ==============================================================================
# Purpose: Build a real reference sequence database, train the bivariate-normal
#   self-vs-non-self likelihood model, and apply it to real BLAST query output
#   to produce TaxaAssign-ready likelihoods.
#
# Audience: someone learning TaxaLikely's SEQUENCE/eDNA pathway step by step.
#   Continues directly from TaxaMatch's blast_sequences_workflow.R.
#
# THIS IS THE SECOND SCRIPT IN A TWO-PACKAGE MINI-CHAIN:
#   TaxaMatch (blast_sequences_workflow.R) -> TaxaLikely (this script)
# It stops at the likelihood object -- does not continue to TaxaAssign/
# TaxaFlag, same scope boundary as the image/acoustic mini-chain.
#
# ARCHITECTURALLY DIFFERENT FROM IMAGE/ACOUSTIC: this is the ONE data type
# that needs the actual bivariate-normal self-vs-non-self model
# (build_sequence_matrix() -> train_likelihood_model()) -- image/acoustic use
# unreferenced_candidates() + assign_scores() to calibrate a PRE-TRAINED
# classifier's output with no training step of their own. Here, TaxaLikely
# does the training itself, from a reference sequence database.
#
# NO SYNTHETIC DATA: the reference database is fetched live from NCBI for the
# 6 real genera spanning the 3 fish families already validated by TaxaMatch's
# script (Cottidae, Embiotocidae, Clinidae) -- the same real PtConception
# study system, not a separate invented example. Query side reuses TaxaMatch's
# real BLAST checkpoint (5 real 12S sequences, 5/5 correctly identified).
#
# Output: taxalikely_sequence_likelihoods -- see the "Output" block at the end
#   of this file for the full column contract.
# ==============================================================================

# --- Namespaces used in this script (loaded, never attached) ----------------
# TaxaLikely::, TaxaTools::

# ==============================================================================
# CONFIG
# ==============================================================================
# Parameters are grouped here so this script's body can become a wrapper
# function's implementation with minimal changes -- each CONFIG value maps to
# a future function argument.

CHECKPOINT_PATH <- file.path(tempdir(), "tutorial_ptconception_blast_taxamatch_blast_match_obj.rds")

# DEBUG_MODE = TRUE  -> live-fetch a real reference sequence database from
#                       NCBI for the 6 genera below (~narrow but real, same
#                       reasoning as TaxaFetch's single-genus Gadus tutorial).
# DEBUG_MODE = FALSE -> plug in your own reference_df (see the
#                       "SWAP IN YOUR OWN DATA" block below)
DEBUG_MODE <- TRUE

RANK_SYSTEM <- c("family", "genus", "species")

# Genera chosen to match TaxaMatch's blast_sequences_workflow.R query set
# (Clinocottus recalvus, Rhacochilus toxotes, Gibbonsia montereyensis,
# Oligocottus snyderi, Embiotoca caryi) plus Phanerodon -- a genus that
# script's own live BLAST run already surfaced as a real confusable congener
# (Phanerodon vacca) within Embiotoca's family. Multiple genera across 3
# families gives the model real within-genus (H2) and cross-genus (H3)
# training pairs, not just within-species (H1) ones.
REFERENCE_TAXA <- c("Clinocottus", "Rhacochilus", "Gibbonsia", "Oligocottus",
                    "Embiotoca", "Phanerodon")
BARCODE_TERM      <- "12S"
MAX_PER_SPECIES   <- 5L   # stratified downsampling -- keeps this tutorial fast

if (!file.exists(CHECKPOINT_PATH)) {
  stop("Checkpoint not found at ", CHECKPOINT_PATH, ". Run TaxaMatch's ",
       "blast_sequences_workflow.R first (in the SAME R session if ",
       "tempdir() has not been reused -- tempdir() is scoped to one R ",
       "session, exactly as documented for the five-package Gadus chain).")
}

taxamatch_blast_match_obj <- readRDS(CHECKPOINT_PATH)
message("Loaded TaxaMatch's checkpoint: ", CHECKPOINT_PATH,
        " (", nrow(taxamatch_blast_match_obj), " row(s), ",
        length(unique(taxamatch_blast_match_obj$observation_id)), " quer(ies)).")

if (DEBUG_MODE) {

  message("\nDEBUG_MODE = TRUE -- fetching a real reference sequence ",
          "database from NCBI for ", length(REFERENCE_TAXA), " genera: ",
          paste(REFERENCE_TAXA, collapse = ", "), ".")

} else {

  # ==========================================================================
  # >>> SWAP IN YOUR OWN DATA <<<
  # ==========================================================================
  # Replace the fetch below with your own reference database, via
  # TaxaLikely::fetch_ncbi_reference_sequences() (broader NCBI search) or
  # TaxaLikely::read_reference_fasta() / read_crabs_output() (local FASTA):
  #
  #   reference_df <- TaxaLikely::fetch_ncbi_reference_sequences(
  #     taxa = c("YourFamily1", "YourGenus2"), barcode_term = "YourMarker",
  #     rank_system = RANK_SYSTEM
  #   )
  #   # or: reference_df <- TaxaLikely::read_reference_fasta(
  #   #   "my_references.fasta", taxonomy = my_taxonomy_df,
  #   #   rank_system = RANK_SYSTEM
  #   # )
  #
  # Set DEBUG_MODE <- FALSE above and fill in the values here.
  # ==========================================================================
  stop("DEBUG_MODE is FALSE but no real reference data has been supplied. ",
       "Edit the 'SWAP IN YOUR OWN DATA' block in this script.")
}

# Output location for checkpoint files (see explicit-checkpoint pattern below)
OUT_DIR    <- tempdir()
OUT_PREFIX <- "tutorial_ptconception_seqmodel"

# ==============================================================================
# 1.  FETCH REFERENCE SEQUENCES -- LIVE NCBI CALL
# ==============================================================================
# fetch_ncbi_reference_sequences() does a count-first estimation before committing
# to any download, then fetches, filters, and resolves taxonomy. Resumable
# via cache_dir (default tools::R_user_dir("TaxaLikely","cache")) -- a
# second run with identical parameters reuses the cache instead of
# re-querying NCBI.
# ==============================================================================

message("\n--- Step 1: Fetching reference sequences from NCBI ---")

reference_df <- TaxaLikely::fetch_ncbi_reference_sequences(
  taxa            = REFERENCE_TAXA,
  barcode_term    = BARCODE_TERM,
  rank_system     = RANK_SYSTEM,
  max_per_species = MAX_PER_SPECIES
)

message(sprintf(
  "  Fetched %d sequence(s): %d unique species, %d unique genera.",
  nrow(reference_df), length(unique(reference_df$species)),
  length(unique(reference_df$genus))
))

# ==============================================================================
# 2.  BUILD THE PAIRWISE SEQUENCE MATRIX -- DECIPHER ALIGNMENT
# ==============================================================================
# Aligns all reference sequences and computes pairwise distances -> pair
# format for train_likelihood_model(). This is the most time-consuming step,
# though trivially fast at this tutorial's scale (a few dozen sequences).
# ==============================================================================

message("\n--- Step 2: Building pairwise sequence matrix (DECIPHER) ---")

ref_matrix <- TaxaLikely::build_sequence_matrix(
  reference_df = reference_df,
  rank_system  = RANK_SYSTEM,
  barcode_term = BARCODE_TERM   # same term used at fetch time; guards against
                                # off-target same-length, wrong-window sequences
                                # slipping past the generic default length filter
)

message(sprintf("  %d pairwise comparison(s) built.", nrow(ref_matrix)))

# ==============================================================================
# 3.  CALIBRATE AND APPLY A COVERAGE FILTER
# ==============================================================================
# Within-species (H1) pairs nearly always have coverage = 1 (same amplicon);
# low-coverage pairs are almost entirely cross-species. calibrate_coverage_
# filter() sweeps thresholds and returns Youden's J (H1 retention minus H2
# retention) to find the Pareto-optimal cutoff. On a small/clean reference
# set coverage may be near-categorical (few unique values) -- the function
# messages when this makes J close to flat; coverage_threshold()'s quantile
# shortcut is used as a fallback in that case.
# ==============================================================================

message("\n--- Step 3: Calibrating coverage filter ---")

.cal <- TaxaLikely::calibrate_coverage_filter(ref_matrix)
.best_thresh <- .cal$threshold[which.max(.cal$youden_j)]

if (length(unique(.cal$youden_j)) <= 1L) {
  message("  Youden's J is flat (categorical/near-constant coverage) -- ",
          "falling back to coverage_threshold()'s quantile shortcut.")
  .best_thresh <- TaxaLikely::coverage_threshold(ref_matrix)
}

message(sprintf("  Coverage threshold: %.3f", .best_thresh))

ref_matrix_filtered <- ref_matrix[ref_matrix$coverage >= .best_thresh, ]
message(sprintf(
  "  Pairs retained after coverage filter: %d of %d (%.1f%%).",
  nrow(ref_matrix_filtered), nrow(ref_matrix),
  100 * nrow(ref_matrix_filtered) / nrow(ref_matrix)
))

# ==============================================================================
# 4.  TRAIN THE LIKELIHOOD MODEL
# ==============================================================================
# The model is ALWAYS bivariate: (score_logit, gap_logit). Estimates H1
# (per-species, Empirical-Bayes-shrunk), H2 (unreferenced species, within
# genus), and H3 (unreferenced genus) parameters from the reference-vs-
# reference training pairs above. use_hierarchy = TRUE falls back gracefully
# to the global mean if lme4 cannot fit (documented footgun -- small/thin
# tutorial data may trigger this fallback; not an error).
# ==============================================================================

message("\n--- Step 4: Training the likelihood model ---")

taxalikely_sequence_model <- TaxaLikely::train_likelihood_model(
  raw_df        = ref_matrix_filtered,
  rank_system   = RANK_SYSTEM,
  prior_weight  = 10.0,
  use_hierarchy = TRUE
)

.interp <- TaxaLikely::interpret_model(taxalikely_sequence_model)
message(sprintf(
  "  Species in model: %d (%d singleton(s)). H1/H2/H3 expected match %%: see interp$hypothesis_baselines.",
  taxalikely_sequence_model$Stats$n_species, taxalikely_sequence_model$Stats$n_singletons
))
print(.interp$hypothesis_baselines)

# ---- Explicit checkpoint (not automatic) ------------------------------------
# The trained model is the expensive artifact here -- checkpoint it
# separately from the final likelihoods so future query batches can skip
# Steps 1-4 entirely.
taxalikely_sequence_model_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_taxalikely_sequence_model.rds"))
saveRDS(taxalikely_sequence_model, taxalikely_sequence_model_path)
message(sprintf("\n  Saved: %s", taxalikely_sequence_model_path))
message(sprintf("  To reuse without re-fetching/re-training, paste:\n    taxalikely_sequence_model <- readRDS(\"%s\")",
                taxalikely_sequence_model_path))

# ==============================================================================
# 5.  REMOVE FLAGGED REFERENCE ERRORS FROM THE QUERY MATCH OBJECT
# ==============================================================================
# train_likelihood_model() calls flag_reference_errors() internally and
# stores the result in model$reference_errors -- mislabeled reference
# accessions the query match object's candidates may point to.
# ==============================================================================

message("\n--- Step 5: Removing flagged reference errors ---")

taxamatch_blast_match_obj_clean <- TaxaLikely::remove_flagged_references(
  taxamatch_blast_match_obj, taxalikely_sequence_model$reference_errors
)

message(sprintf(
  "  %d row(s) removed (%d -> %d).",
  nrow(taxamatch_blast_match_obj) - nrow(taxamatch_blast_match_obj_clean),
  nrow(taxamatch_blast_match_obj), nrow(taxamatch_blast_match_obj_clean)
))

# ==============================================================================
# 6.  EVALUATE LIKELIHOODS
# ==============================================================================
# Applies the trained model to the real query match object from TaxaMatch.
# min_coverage reuses the SAME threshold calibrated on the training data
# (Step 3) -- keeps inference within the coverage range the model was
# trained on. taxamatch_blast_match_obj already has a 'coverage' column
# (from blast_sequences_workflow.R's coverage_col = "query_coverage"), so no
# extra join is needed here.
# ==============================================================================

message("\n--- Step 6: Evaluating likelihoods ---")

taxalikely_sequence_lik_result <- TaxaLikely::evaluate_likelihoods(
  match_df     = taxamatch_blast_match_obj_clean,
  model_params = taxalikely_sequence_model,
  rank_system  = RANK_SYSTEM,
  n_sims       = 200L,
  min_coverage = .best_thresh
)

taxalikely_sequence_likelihoods <- taxalikely_sequence_lik_result$likelihoods

message(sprintf("  %d likelihood row(s) across %d quer(ies).",
                nrow(taxalikely_sequence_likelihoods),
                length(unique(taxalikely_sequence_likelihoods$observation_id))))
message("  hypothesis_type distribution:")
print(table(taxalikely_sequence_likelihoods$hypothesis_type))

if (nrow(taxalikely_sequence_lik_result$unresolved) > 0L) {
  message(sprintf(
    "  %d quer(ies) unresolved at rank_system = %s -- re-run evaluate_likelihoods() ",
    length(unique(taxalikely_sequence_lik_result$unresolved$observation_id)),
    paste(RANK_SYSTEM, collapse = "/")
  ), "on $unresolved with a coarser rank_system if needed.")
}

# ---- Filter to finest-rank candidates per query -----------------------------
taxalikely_sequence_likelihoods <- TaxaLikely::filter_top_hypotheses(
  taxalikely_sequence_likelihoods, rank_system = RANK_SYSTEM
)

# ---- Honesty check: does the winning specific_candidate match ground truth? -
# This is a real accuracy check on real data, not a synthetic sanity check --
# useful to report even though it isn't part of the likelihood object itself.
# true_species was carried through from TaxaMatch's checkpoint (tutorial-only
# column) but is NOT part of evaluate_likelihoods()'s fixed output schema, so
# it is re-joined here from the query match object.
.true_lookup <- unique(taxamatch_blast_match_obj[, c("observation_id", "true_species")])
.top1 <- taxalikely_sequence_likelihoods[
  taxalikely_sequence_likelihoods$hypothesis_type == "specific_candidate",
]
.top1 <- .top1[order(.top1$observation_id, -.top1$score_likelihood), ]
.top1 <- .top1[!duplicated(.top1$observation_id), ]
.top1 <- merge(.top1, .true_lookup, by = "observation_id", all.x = TRUE)
message(sprintf(
  "\n  Top-likelihood accuracy: %d/%d correct (%.0f%%).",
  sum(.top1$taxon_name == .top1$true_species),
  nrow(.top1),
  100 * mean(.top1$taxon_name == .top1$true_species)
))

# ---- Explicit checkpoint (not automatic) ------------------------------------
taxalikely_sequence_likelihoods_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_taxalikely_sequence_likelihoods.rds"))
saveRDS(taxalikely_sequence_likelihoods, taxalikely_sequence_likelihoods_path)
message(sprintf("\n  Saved: %s", taxalikely_sequence_likelihoods_path))
message(sprintf("  To reuse without re-running this script, paste:\n    taxalikely_sequence_likelihoods <- readRDS(\"%s\")",
                taxalikely_sequence_likelihoods_path))

message("\nWorkflow complete. This mini-chain stops here -- see TaxaMatch's ",
        "blast_sequences_workflow.R header comment for why it does not ",
        "continue to TaxaAssign/TaxaFlag.")

# ==============================================================================
# Output
# ==============================================================================
# taxalikely_sequence_likelihoods -- one row per observation_id x taxon
#   hypothesis, REAL trained-model output for 5 real PtConception 12S query
#   sequences against a REAL NCBI reference database (6 genera, 3 families):
#
#   observation_id       -- character; query identifier (BLAST accession)
#   taxon_name            -- character; hypothesized taxon (never NA)
#   taxon_name_rank        -- character; rank of taxon_name
#   hypothesis_type        -- character; "specific_candidate" (H1),
#                            "unreferenced_species" (H2), or
#                            "unreferenced_genus" (H3)
#   score_likelihood        -- numeric; point estimate (deterministic)
#   score_likelihood_mean    -- numeric; mean across Monte Carlo simulations
#   score_likelihood_sd      -- numeric; SD across simulations
#   score_likelihood_cov     -- numeric; coverage-adjusted point estimate
#
# Consumer: TaxaAssign::compute_posterior() (not run in this mini-chain --
#   see TaxaMatch's blast_sequences_workflow.R header for scope boundary).
# ==============================================================================
