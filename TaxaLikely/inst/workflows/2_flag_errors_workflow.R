# ==============================================================================
# WORKFLOW 2: FLAG REFERENCE DATABASE ERRORS
# ==============================================================================
# DATA TYPE SCOPE: DNA sequences only.
#   For Xeno-canto acoustic data, use quality grade filtering in Workflow 3b
#   (quality = c("A", "B") in fetch_reference_recordings()) instead of this
#   workflow. Xeno-canto is expert-curated; mislabeling is rare, and flagging
#   would remove legitimate hard-case recordings.
#   For image (camera trap) data, guidance is TBD pending read_animl_output().
#
# Purpose: Identify mislabeled or suspect sequences in a reference database.
#   Mislabeled references corrupt model training and produce misleading
#   likelihood estimates. Finding them is an important QC step.
#
# Input: reference_df from Workflow 1 (or a pre-built pairwise matrix)
# Output: A table of flagged sequences with error types and diagnostics
#
# Error types detected:
#   "likely_mislabeled"                 -- sequence matches a foreign species
#       better than its own label (strong evidence of mislabeling)
#   "unverified_singleton_high_match"   -- only representative of its species,
#       but matches a foreign species at >= 98% (suspicious but ambiguous)
#
# What to do with errors:
#   - Inspect them (this workflow shows how)
#   - Remove them before training a model (Workflow 3 does this automatically)
#   - Remove them from your match object before evaluating likelihoods
#     (Workflow 4 shows this step)
#   - Optionally report them to the database maintainer
#
# Requires: DECIPHER and Biostrings (for build_sequence_matrix)
#   Install with: BiocManager::install("DECIPHER")
# ==============================================================================

library(TaxaLikely)

# ---- 1. Load reference_df ---------------------------------------------------
# From Workflow 1 (fetch_reference_sequences or read_reference_fasta)
reference_df <- readRDS("reference_df.rds")
cat("reference_df:", nrow(reference_df), "sequences,",
    length(unique(reference_df$species)), "species\n")

# ---- 2. Build pairwise distance matrix --------------------------------------
# This aligns all sequences and computes pairwise distances.
# Can take several minutes for large databases (100+ sequences).
# The result is reusable: save it for Workflow 3 (model training).

rank_system <- c("family", "genus", "species")

ref_matrix <- build_sequence_matrix(
  reference_df = reference_df,
  rank_system  = rank_system
  # max_dist = 0.25    # pairs above 25% divergence are dropped (default)
  # min_seq_len = 100  # drop short sequences
  # max_seq_len = 2000 # drop very long sequences
)

cat("Matrix:", nrow(ref_matrix), "pairwise comparisons\n")

# Save the matrix -- it's expensive to rebuild
saveRDS(ref_matrix, "ref_matrix.rds")

# ---- 3. Flag errors ----------------------------------------------------------
# flag_reference_errors() examines each sequence's within-species vs
# cross-species match scores. If a sequence matches a foreign species
# better than its own conspecifics, it is flagged.

errors <- flag_reference_errors(
  raw_df            = ref_matrix,
  mislabel_threshold = 0.02,    # margin (in p_match units) required
  return_all        = FALSE    # TRUE to also see "clean" sequences
)

cat("\nFlagged sequences:", nrow(errors), "\n")
if (nrow(errors) > 0) print(errors)

# ---- 4. Explore errors -------------------------------------------------------

# 4a. How many of each type?
if (nrow(errors) > 0) {
  cat("\nError type summary:\n")
  print(table(errors$error_type))
}

# 4b. Which species are most affected?
if (nrow(errors) > 0) {
  cat("\nSpecies with most flagged sequences:\n")
  print(sort(table(errors$species_x), decreasing = TRUE))
}

# 4c. Look at the integrity gap distribution
# Negative gap = foreign match is better than self match (bad sign)
if (nrow(errors) > 0) {
  cat("\nIntegrity gap summary (should be negative for mislabeled):\n")
  print(summary(errors$integrity_gap))
}

# 4d. Full QC report (including clean sequences)
all_qc <- flag_reference_errors(ref_matrix, return_all = TRUE)
cat("\nOverall QC summary:\n")
print(table(all_qc$error_type))

# Histogram of integrity gaps across all sequences
hist(all_qc$integrity_gap,
     main = "Integrity gap distribution (all sequences)",
     xlab = "Integrity gap (self - foreign match score)",
     breaks = 30)
abline(v = 0, col = "red", lty = 2)

# 4e. Singleton analysis
# Singletons have no within-species neighbors -- can't compute integrity gap.
# They aren't necessarily errors, but high foreign matches are suspicious.
singletons <- all_qc[all_qc$n_self_neighbors == 0, ]
cat("\nSingletons:", nrow(singletons), "of", nrow(all_qc), "sequences\n")
if (nrow(singletons) > 0) {
  cat("Singletons with high foreign match (>0.95):\n")
  print(singletons[singletons$max_foreign_match > 0.95, ])
}

# ---- 5. Save error list for downstream use -----------------------------------
# Workflow 3 (train_model_workflow.R) uses flag_reference_errors() internally,
# so you don't need to pass the error list there.
#
# But you SHOULD filter your match object against these errors before
# running Workflow 4 (score_to_likelihood_workflow.R). See that workflow
# for the one-liner to do so.

if (nrow(errors) > 0) {
  saveRDS(errors, "reference_errors.rds")
  message("Saved reference_errors.rds (", nrow(errors), " flagged sequences)")

  # Optional: export as CSV for sharing with collaborators / database curators
  # write.csv(errors, "reference_errors.csv", row.names = FALSE)
}

message("\nWorkflow 2 complete.")
message("Next: Workflow 3 (train model) or Workflow 4 (score to likelihood)")
