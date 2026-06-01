# ==============================================================================
# WORKFLOW 6: NO-SCORE PATHWAY — PRIOR-BASED CANDIDATE EXPANSION
# ==============================================================================
# Purpose: Build a likelihood object for observations that have a consensus
#   taxon assignment but no match scores. Bypasses TaxaMatch and the likelihood
#   model entirely. Posteriors computed by TaxaAssign will be proportional to
#   TaxaExpect priors.
#
# When to use this pathway:
#   - Morphology-based or expert identifications (no barcode data)
#   - Upranked consensus outputs (score discrimination failed at species level)
#   - Legacy databases with taxon names but no similarity scores
#   - Mixed datasets: combine with scored likelihoods before TaxaAssign
#
# Input:
#   consensus_df  -- observation_id + taxon_name + taxon_name_rank (no score)
#   priors_df     -- from TaxaExpect; species + taxonomy + prior columns
#
# Output:
#   likelihoods   -- degenerate likelihood object (all likelihoods = 1.0)
#                    structurally identical to evaluate_likelihoods() output;
#                    pass directly to TaxaAssign::compute_posterior()
#
# Candidate construction by rank:
#   Species → consensus species + unreferenced congeners (in priors_df but
#             not in referenced_species; referenced congeners already competed
#             via scores in the original pipeline and lost)
#   Genus   → all species in that genus present in priors_df (referenced
#             species included — score discrimination failed)
#   Family  → all species in that family present in priors_df (guarded by
#             max_candidates to avoid unwieldy candidate sets)
#
# Steps:
#   1. Load consensus assignments and TaxaExpect priors
#   2. expand_consensus_candidates() → degenerate likelihood object
#   3. Inspect candidate set
#   4. (Optional) Combine with scored likelihoods from Workflow 4
#   5. Save for TaxaAssign
# ==============================================================================

library(TaxaLikely)
library(dplyr)

# Auto-detect TaxaID root (works whether wd is TaxaID/ or TaxaLikely/)
.taxa_root <- normalizePath(
  if (basename(getwd()) == "TaxaLikely") ".." else ".",
  mustWork = FALSE
)

# ---- 1. Load inputs ----------------------------------------------------------

# Consensus assignments: one row per observation, no score column required.
# Required columns: observation_id, taxon_name, taxon_name_rank
# taxon_name_rank must be one of: "species", "genus", "family"
#
# Example sources:
#   - Morphology field sheets imported from CSV
#   - Upranked rows from TaxaAssign::posterior_consensus() (taxon_name_rank != "species")
#   - A previous run's consensus output filtered to no-score observations
consensus_df <- readRDS(file.choose())   # select your consensus .rds or .csv

# If loading from CSV:
# consensus_df <- read.csv("my_morphology_ids.csv")
# Required columns: observation_id, taxon_name, taxon_name_rank

cat("Consensus assignments:", nrow(consensus_df), "rows\n")
cat("Rank breakdown:\n")
print(table(consensus_df$taxon_name_rank, useNA = "ifany"))

# Priors from TaxaExpect.
# Must contain: species (binomial), genus, family columns (for filtering)
# plus prior_alpha, prior_beta (or equivalent) for TaxaAssign.
priors_df <- readRDS(file.path(.taxa_root, "TaxaExpect/priors.rds"))

cat("\nPriors available for", length(unique(priors_df$species)), "species\n")

# Reference species list (for species-level consensus rows only).
# These are species WITH barcode/reference sequences -- they would have
# competed via match scores and are excluded as congener candidates.
# Source: your reference_df$species, or the skip-list from audit_barcode_coverage().
# Set to NULL if all observations are at genus/family level.
#
# Example:
# reference_df    <- readRDS(file.path(.taxa_root, "TaxaLikely/reference_df.rds"))
# referenced_species <- unique(reference_df$species)
referenced_species <- NULL   # replace with a character vector if applicable

# ---- 2. Expand consensus to candidate set ------------------------------------
# expand_consensus_candidates() returns list($likelihoods, $unresolved).
# $likelihoods is structurally identical to evaluate_likelihoods() output.
#
# Skip filter_top_hypotheses() -- all likelihoods are uniform (1.0), so rank
#   filtering has no effect.
# Skip apply_coverage_constraints() -- all candidates are "specific_candidate";
#   the coverage suppression logic targets "unreferenced_species" rows.

result <- expand_consensus_candidates(
  consensus_df       = consensus_df,
  priors_df          = priors_df,
  referenced_species = referenced_species,  # NULL if no scored pathway was run
  max_candidates     = 50L   # family-level guard; lower if priors_df is dense
)

likelihoods <- result$likelihoods
cat("\nLikelihood rows:", nrow(likelihoods), "\n")
cat("Observations expanded:", dplyr::n_distinct(likelihoods$observation_id), "\n")

# ---- 3. Inspect candidate set ------------------------------------------------

# Candidates per observation
cand_counts <- likelihoods |>
  dplyr::count(observation_id, name = "n_candidates") |>
  dplyr::arrange(dplyr::desc(n_candidates))

cat("\nCandidate count summary:\n")
print(summary(cand_counts$n_candidates))

cat("\nObservations with >10 candidates (family-level):\n")
print(subset(cand_counts, n_candidates > 10))

# Unresolved observations (no candidates found in priors_df)
if (nrow(result$unresolved) > 0L) {
  cat("\nUnresolved observations:", nrow(result$unresolved), "\n")
  cat("taxon_name values:\n")
  print(unique(result$unresolved$taxon_name))
  cat("Consider: Is the taxon name in priors_df? Does genus/family column exist?\n")
  cat("Unresolved rows will need manual handling or a coarser prior query.\n")
} else {
  cat("\nAll observations resolved.\n")
}

# ---- 4. (Optional) Combine with scored likelihoods from Workflow 4 -----------
# If you ran Workflow 4 on observations WITH match scores, combine both
# likelihood objects before passing to TaxaAssign. The two pathways produce
# identical output structures.

# scored_likelihoods <- readRDS("likelihoods_scored.rds")
# likelihoods_combined <- dplyr::bind_rows(scored_likelihoods, likelihoods)
#
# Check for observation_id overlap (should be none if datasets are disjoint):
# overlap <- intersect(scored_likelihoods$observation_id, likelihoods$observation_id)
# if (length(overlap) > 0) warning(length(overlap), " overlapping observation_ids")
#
# likelihoods <- likelihoods_combined   # use combined set below

# ---- 5. Save for TaxaAssign --------------------------------------------------
saveRDS(likelihoods, "likelihoods_no_score.rds")
message("Saved likelihoods_no_score.rds")

# Pass directly to TaxaAssign::compute_posterior().
# Posteriors will be proportional to priors (uniform likelihoods cancel out).
# This is equivalent to prior-only assignment, made explicit:
#
# posteriors <- TaxaAssign::compute_posterior(
#   likelihoods,
#   priors_df = priors_df
# )

message("\nWorkflow 6 complete.")
message("Next: TaxaAssign::compute_posterior() for posterior assignment")
