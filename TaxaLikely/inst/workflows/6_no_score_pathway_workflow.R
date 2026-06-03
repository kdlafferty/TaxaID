# ==============================================================================
# WORKFLOW 6: NO-SCORE PATHWAY — CANDIDATE EXPANSION WITHOUT MATCH SCORES
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
# Required columns in consensus_df:
#   observation_id, taxon_name, taxon_name_rank
#   PLUS taxonomy columns: family, genus, species
#   (needed by unreferenced_candidates() to build H2/H3 placeholder rows)
#
# ⚠️  posterior_consensus() output does NOT carry family/genus/species columns.
#   If your consensus_df comes from posterior_consensus(), join taxonomy back
#   from the original match_df first (see Section 1b below).
#
# Output:
#   likelihoods   -- degenerate likelihood object (all likelihoods = 1.0)
#                    structurally identical to evaluate_likelihoods() output;
#                    pass directly to TaxaAssign::compute_posterior()
#
# Candidate construction (Session 99+):
#   unreferenced_candidates() adds two placeholder rows per observation:
#     H2 (unreferenced_species) -- same genus as the consensus taxon
#     H3 (unreferenced_genus)   -- same family as the consensus taxon
#   assign_scores(score_type = "none") then sets all score_likelihood = 1.0.
#   Posteriors are proportional entirely to TaxaExpect priors.
#
# Steps:
#   1. Load consensus assignments (+ taxonomy join if from posterior_consensus)
#   2. unreferenced_candidates() — add H2/H3 placeholders
#   3. assign_scores(score_type = "none") — uniform likelihoods
#   4. Inspect candidate set
#   5. (Optional) Combine with scored likelihoods from Workflow 4
#   6. Save for TaxaAssign
# ==============================================================================

library(TaxaLikely)
library(dplyr)

# Auto-detect TaxaID root (works whether wd is TaxaID/ or TaxaLikely/)
.taxa_root <- normalizePath(
  if (basename(getwd()) == "TaxaLikely") ".." else ".",
  mustWork = FALSE
)

# ---- 1a. Load consensus assignments ------------------------------------------
# One row per observation; no score column required.
consensus_df <- readRDS(file.choose())   # select your consensus .rds or .csv

# If loading from CSV:
# consensus_df <- read.csv("my_morphology_ids.csv")

# If input is posterior_consensus() output, rename columns to match interface:
if ("consensus_taxon" %in% names(consensus_df) && !"taxon_name" %in% names(consensus_df)) {
  consensus_df$taxon_name      <- consensus_df$consensus_taxon
  consensus_df$taxon_name_rank <- consensus_df$consensus_rank
}

cat("Consensus assignments:", nrow(consensus_df), "rows\n")
cat("Rank breakdown:\n")
print(table(consensus_df$taxon_name_rank, useNA = "ifany"))

# ---- 1b. Join taxonomy columns (required if from posterior_consensus) ---------
# unreferenced_candidates() needs family, genus, and species columns to build
# H2/H3 placeholder rows. posterior_consensus() output does not carry these —
# join them back from the original match_df.
#
# Skip this block if your consensus_df already has family/genus/species
# (e.g., from a CSV with full taxonomy, or from standardize_match_data output).

if (!all(c("family", "genus", "species") %in% names(consensus_df))) {
  message("Joining taxonomy columns from match_df (family, genus, species not found in consensus_df)")
  match_df <- readRDS(file.choose())   # select the match_obj.rds used to generate the consensus

  # Normalize legacy column names if needed (pre-Session 79/99 files)
  if (!"observation_id" %in% names(match_df)) {
    old <- intersect(c("sample_id", "esvid", "esv_id"), names(match_df))[1]
    if (!is.na(old)) names(match_df)[names(match_df) == old] <- "observation_id"
  }

  tax_cols <- match_df |>
    dplyr::distinct(taxon_name, family, genus, species)

  consensus_df <- consensus_df |>
    dplyr::left_join(tax_cols, by = "taxon_name")

  n_missing <- sum(is.na(consensus_df$family))
  if (n_missing > 0L)
    warning(n_missing, " observation(s) could not be matched to taxonomy in match_df. ",
            "These will produce only 1 hypothesis row (no H2/H3).")
}

# ---- 2. Add H2/H3 placeholder rows -------------------------------------------
# unreferenced_candidates() adds:
#   "unreferenced_species" row -- genus represented but species unknown
#   "unreferenced_genus"   row -- family represented but genus unknown
#
# include_unreferenced_family = FALSE (default) is appropriate when using
# TaxaExpect priors — the prior distribution already covers unrepresented
# families. Set to TRUE only when running without TaxaExpect priors (e.g. the
# LLM shortcut pathway) to add an additional catch-all row.

hyp_df <- unreferenced_candidates(
  match_df    = consensus_df,
  rank_system = c("family", "genus", "species"),   # adjust to match your data
  include_unreferenced_family = FALSE
)

cat("\nHypothesis rows after expansion:", nrow(hyp_df), "\n")
cat("Hypothesis types:\n")
print(table(hyp_df$hypothesis_type))

# ---- 3. Assign uniform likelihoods -------------------------------------------
# score_type = "none": all rows receive score_likelihood = 1.0.
# Posteriors will be proportional entirely to TaxaExpect priors.

likelihoods <- assign_scores(
  hypotheses_df = hyp_df,
  score_type    = "none"
)

cat("\nLikelihood rows:", nrow(likelihoods), "\n")
cat("Observations expanded:", dplyr::n_distinct(likelihoods$observation_id), "\n")
stopifnot(all(likelihoods$score_likelihood == 1.0))

# ---- 4. Inspect candidate set ------------------------------------------------

cand_counts <- likelihoods |>
  dplyr::count(observation_id, name = "n_candidates") |>
  dplyr::arrange(dplyr::desc(n_candidates))

cat("\nCandidate count summary:\n")
print(summary(cand_counts$n_candidates))

# All observations should produce exactly 3 rows (H1 + H2 + H3).
# Fewer rows mean a taxonomy column was missing for H2/H3 derivation.
obs_with_fewer <- cand_counts[cand_counts$n_candidates < 3L, ]
if (nrow(obs_with_fewer) > 0L) {
  cat("\nObservations with fewer than 3 hypothesis rows:\n")
  print(obs_with_fewer)
  cat("Check that 'family', 'genus', and 'species' columns are present (Section 1b).\n")
} else {
  cat("\nAll observations have 3 candidate rows (H1 + H2 + H3).\n")
}

# ---- 5. (Optional) Combine with scored likelihoods from Workflow 4 -----------
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

# ---- 6. Save for TaxaAssign --------------------------------------------------
saveRDS(likelihoods, "likelihoods_no_score.rds")
message("Saved likelihoods_no_score.rds")

# Pass directly to TaxaAssign::compute_posterior().
# Posteriors will be proportional to priors (uniform likelihoods cancel out).
# Supply TaxaExpect priors via join_priors() or run_bayesian_pipeline() before
# calling compute_posterior().
#
# Example:
# priors_joined <- TaxaAssign::join_priors(
#   likelihoods,
#   priors_df    = taxaexpect_priors,
#   main_habitat = "freshwater"
# )
# posteriors <- TaxaAssign::compute_posterior(priors_joined, n_sims = 1000L)

message("\nWorkflow 6 complete.")
message("Next: TaxaAssign::join_priors() + compute_posterior() for posterior assignment")
