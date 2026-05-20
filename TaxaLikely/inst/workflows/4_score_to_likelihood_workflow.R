# ==============================================================================
# WORKFLOW 4: CONVERT MATCH SCORES TO LIKELIHOODS
# ==============================================================================
# Purpose: Apply a trained model to a match object (from TaxaMatch or
#   user-supplied) to produce per-hypothesis likelihoods for TaxaAssign.
#
# This is the workflow most users will run routinely. It takes:
#   1. A match_df (one row per observation_id x reference accession match)
#   2. A trained model (from Workflow 3)
#   3. Optionally, a reference error list (from Workflow 2)
# And produces likelihoods for three hypothesis types:
#   H1 (specific_candidate) -- the matching species is correct
#   H2 (unreferenced_species) -- the true species is absent from the reference
#   H3 (unreferenced_genus) -- the true genus is absent from the reference
#
# Output goes to TaxaAssign for posterior probability calculation.
# ==============================================================================

library(TaxaLikely)
library(dplyr)
# ---- 1. Load inputs ----------------------------------------------------------

# Match object: one row per observation_id x reference hit.
# Required columns: observation_id, score, taxon_name, taxon_name_rank
# Plus taxonomy columns matching your rank_system (e.g., genus, species)
# Can come from TaxaMatch::standardize_match_data() or user-supplied.
match_df <- readRDS(file.choose())  # select your match data file (.rds)

# Trained model from Workflow 3
model <- readRDS("trained_model.rds")

rank_system <- c("family", "genus", "species")

# Confirm required columns exist
stopifnot(all(c("observation_id", "score", "taxon_name", "taxon_name_rank")
              %in% names(match_df)))
cat("Match object:", nrow(match_df), "rows,",
    length(unique(match_df$observation_id)), "unique queries\n")

# ---- 2. Remove flagged reference errors --------------------------------------
# If you ran Workflow 2 or 3, mislabeled accessions should be removed from
# the match object before evaluating likelihoods. train_likelihood_model()
# stores the error list in model_params$reference_errors, so you can use it
# directly. Alternatively, load errors saved by Workflow 2.
#
# remove_flagged_references() handles version suffix stripping automatically.

errors <- model_params$reference_errors  # from train_likelihood_model()
# Or: errors <- readRDS("reference_errors.rds")  # from Workflow 2

match_df <- remove_flagged_references(match_df, errors)

# ---- 3. Evaluate likelihoods ------------------------------------------------
# evaluate_likelihoods() does the heavy lifting:
#   - Groups candidates by taxon_name, takes max score per taxon
#   - Logit-transforms and computes the gap (best vs runner-up)
#   - Looks up species-specific model parameters (with global fallback)
#   - Evaluates H1/H2/H3 likelihoods for each query
#   - Runs Monte Carlo for uncertainty estimates (likelihood_mean, likelihood_sd)
#
# The output contains three types of hypotheses per query:
#
#   "specific_candidate" (H1) -- a referenced species. Each gets its own
#     likelihood based on its species-specific score distribution. Wrong
#     candidates get low likelihoods because their observed score falls in
#     the tail of their expected distribution.
#
#   "unreferenced_species" (H2) -- a placeholder for species not in the
#     reference but whose genus IS represented. Without this, the model
#     would be forced to assign all probability to referenced species,
#     even when the true source is absent.
#
#   "unreferenced_genus" (H3) -- a placeholder for genera not in the
#     reference at all. Catches distant matches.
#
# Returns a named list with $likelihoods and $unresolved.

lik_result <- evaluate_likelihoods(
  match_df     = match_df,
  model_params = model,
  rank_system  = rank_system,
  n_sims       = 200L          # Monte Carlo iterations (0 = point estimate only)
  # ratio_threshold = 0.001    # drop hypotheses with ratio below this (default)
)



likelihoods <- lik_result$likelihoods
cat("\nLikelihood rows:", nrow(likelihoods), "\n")
cat("Hypothesis types:\n")
print(table(likelihoods$hypothesis_type))
likeli_score_table <- likelihoods |>
  left_join(match_df) |>
  select(observation_id, taxon_name, likelihood_mean, score) |>
  unique() |>
  na.omit()

plot(likeli_score_table$score,likeli_score_table$likelihood_mean)
# ---- 4. Handle unresolved queries --------------------------------------------
# Some observation_ids may produce no usable likelihoods -- typically because all
# candidates matched only at a rank coarser than the finest in rank_system.
# These are returned in $unresolved for re-evaluation with a coarser rank.

if (nrow(lik_result$unresolved) > 0) {
  cat("\nUnresolved queries:", length(unique(lik_result$unresolved$observation_id)), "\n")

  # Option: re-run at a coarser rank
  # lik_coarse <- evaluate_likelihoods(
  #   match_df     = lik_result$unresolved,
  #   model_params = model,
  #   rank_system  = c("order", "family"),
  #   n_sims       = 200L
  # )
  # likelihoods <- rbind(likelihoods, lik_coarse$likelihoods)
} else {
  cat("\nAll queries resolved.\n")
}

# ---- 5. Filter to top hypotheses (optional) ----------------------------------
# filter_top_hypotheses() keeps only the finest-rank candidates per query.
# For example, if a query has both species-level and genus-level candidates,
# it keeps only the species-level ones.
# This is often desirable but not always -- inspect before deciding.

filtered <- filter_top_hypotheses(likelihoods, rank_system = rank_system)
cat("\nAfter filtering to top hypotheses:", nrow(filtered), "rows\n")

# Compare: which queries lost hypotheses?
lost <- setdiff(unique(likelihoods$observation_id), unique(filtered$observation_id))
if (length(lost) > 0) cat("Queries dropped:", length(lost), "\n")

# ---- 6. Inspect results -----------------------------------------------------

# Top candidate per query
top_per_query <- filtered |>
  dplyr::group_by(observation_id) |>
  dplyr::slice_max(likelihood_point_est, n = 1, with_ties = FALSE) |>
  dplyr::ungroup()

cat("\nTop candidate per query (first 10):\n")
print(head(top_per_query[, c("observation_id", "taxon_name", "hypothesis_type",
                              "likelihood_point_est", "likelihood_sd")], 10))

# How confident are the assignments?
cat("\nLikelihood point estimate distribution (top candidates):\n")
print(summary(top_per_query$likelihood_point_est))

# Which queries have high uncertainty?
if (any(top_per_query$likelihood_sd > 0)) {
  uncertain <- top_per_query[top_per_query$likelihood_sd >
                             stats::quantile(top_per_query$likelihood_sd, 0.9,
                                             na.rm = TRUE), ]
  cat("\nHigh-uncertainty queries (top 10% by SD):", nrow(uncertain), "\n")
}

# ---- 7. Save for TaxaAssign -------------------------------------------------
saveRDS(likelihoods, "likelihoods.rds")
message("Saved likelihoods.rds")

# The likelihoods data frame is the input to TaxaAssign::compute_posterior()
# which combines these with priors from TaxaExpect.
# See: TaxaAssign_bayesian_workflow.R or TaxaAssign_llm_workflow.R

message("\nWorkflow 4 complete.")
message("Next: Workflow 5 (audit coverage) or TaxaAssign for posterior assignment")
