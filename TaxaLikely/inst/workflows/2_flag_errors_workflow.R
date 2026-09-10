# ==============================================================================
# WORKFLOW 2: SCREEN REFERENCE DATABASE FOR QUALITY ISSUES
# ==============================================================================
# DATA TYPE SCOPE: DNA sequences only.
#   For Xeno-canto acoustic data, use quality grade filtering in Workflow 3b
#   (quality = c("A", "B") in fetch_reference_recordings()) instead of this
#   workflow. Xeno-canto is expert-curated; mislabeling is rare, and flagging
#   would remove legitimate hard-case recordings.
#   For image (camera trap) data, guidance is TBD pending read_animl_output().
#
# Purpose: Identify mislabeled or suspect sequences in a reference database
#   BEFORE training a likelihood model on it. Mislabeled references corrupt
#   model training and produce misleading likelihood estimates.
#
# Requires TaxaMatch, not just TaxaLikely: reference-quality screening lives
#   in TaxaMatch (corroborate_references_locally() + evaluate_reference_
#   accessions()), not in TaxaLikely -- TaxaLikely::train_likelihood_model()
#   trains on whatever reference_df/ref_matrix it's given, with no built-in
#   screening step (retired 2026-09-08; see NAME_CHANGE_HISTORY.md).
#
# Input: reference_df from Workflow 1
# Output: reference_df with bad accessions excluded, ready for Workflow 3
#
# Two-tier design:
#   1. corroborate_references_locally() -- free, zero-NCBI-cost. Checks
#      whether an INDEPENDENT conspecific already in your own reference set
#      agrees with each accession's label. Most accessions resolve here.
#   2. evaluate_reference_accessions() -- BLASTs against a broad, independent
#      database. Only run for accessions the free check couldn't resolve
#      (skip_locally_corroborated = TRUE skips the rest automatically).
#
# Requires: DECIPHER and Biostrings (for build_sequence_matrix)
#   Install with: BiocManager::install("DECIPHER")
# ==============================================================================

library(TaxaLikely)
library(TaxaMatch)

# ---- 1. Load reference_df ---------------------------------------------------
# From Workflow 1 (fetch_ncbi_reference_sequences or read_reference_fasta)
reference_df <- readRDS("reference_df.rds")
cat(
  "reference_df:", nrow(reference_df), "sequences,",
  length(unique(reference_df$species)), "species\n"
)

# ---- 2. Build pairwise distance matrix --------------------------------------
# This aligns all sequences and computes pairwise distances.
# Can take several minutes for large databases (100+ sequences).
# The result is reusable: save it for Workflow 3 (model training) too.

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

# ---- 3. Free local corroboration check --------------------------------------
# For each accession: does an independent conspecific already in your own
# reference set agree with it at high identity over real overlap? Zero NCBI
# cost -- this is a pure function of ref_matrix/reference_df.

local_corr <- corroborate_references_locally(
  seq_matrix     = ref_matrix,
  reference_meta = reference_df
  # min_overlap = 0.8, min_pident = 0.99  # defaults
)

cat("\nLocal corroboration tiers:\n")
print(table(local_corr$local_tier))

# ---- 4. BLAST-based screen (only for accessions the free check couldn't resolve) ----
# skip_locally_corroborated = TRUE skips every accession local_corr already
# resolved to "corroborated" -- only the remainder costs a real NCBI call.

ref_eval <- evaluate_reference_accessions(
  accessions              = unique(reference_df$composite_id),
  barcode_term            = "MiFishU", # match your own marker
  local_corroboration     = local_corr,
  skip_locally_corroborated = TRUE,
  cache_dir               = "ref_eval_cache" # persists across reruns
)

cat("\nBLAST-based hierarchy_flag summary:\n")
print(table(ref_eval$hierarchy_flag, useNA = "ifany"))

# ---- 5. Derive a keep/remove verdict -----------------------------------------
# score_reference_labels() combines the BLAST verdict with the local
# corroboration evidence into one reference_action per accession.

ref_labeled <- score_reference_labels(ref_eval, local_corroboration = local_corr)

cat("\nreference_action summary:\n")
print(table(ref_labeled$reference_action, useNA = "ifany"))

bad_accessions <- ref_labeled$accession[ref_labeled$reference_action == "remove"]
cat("\n", length(bad_accessions), "accession(s) recommended for removal.\n")
if (length(bad_accessions) > 0) print(ref_labeled[ref_labeled$accession %in% bad_accessions, ])

# ---- 6. Exclude bad accessions before training -------------------------------
# This is what train_likelihood_model() no longer does for you automatically.

reference_df_clean <- reference_df[!reference_df$composite_id %in% bad_accessions, ]
cat(
  "\nreference_df reduced from", nrow(reference_df), "to",
  nrow(reference_df_clean), "sequences after screening.\n"
)

saveRDS(reference_df_clean, "reference_df_clean.rds")
message("Saved reference_df_clean.rds (", nrow(reference_df_clean), " sequences)")

message("\nWorkflow 2 complete.")
message("Next: Workflow 3 (train model on reference_df_clean.rds)")
