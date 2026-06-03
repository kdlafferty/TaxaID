# expand_consensus_demo.R
# Demo for the no-score candidate expansion pathway.
#
# Session 99: expand_consensus_candidates() is DEPRECATED.
# Use unreferenced_candidates() + assign_scores() instead.
# See Workflow 6 (6_no_score_pathway_workflow.R) for the full workflow.
#
# Key difference from the old API:
#   Old: expand_consensus_candidates() enumerated ALL species in the genus or
#        family from priors_df. Required a priors_df + referenced_species list.
#   New: unreferenced_candidates() adds two placeholder rows (H2 = unreferenced
#        species in anchor genus; H3 = unreferenced genus in anchor family).
#        No priors_df required at this stage. TaxaExpect priors are joined
#        later by TaxaAssign::join_priors() or run_bayesian_pipeline().
#
# Run interactively: source("inst/workflows/expand_consensus_demo.R")

library(TaxaLikely)

# ─────────────────────────────────────────────────────────────────────────────
cat("=== Demo 1: Species-level consensus (no scores) ===\n")
cat("'Salmo salar' identified by morphology. All score_likelihood = 1.0.\n\n")

consensus_sp <- data.frame(
  observation_id  = "obs1",
  taxon_name      = "Salmo salar",
  taxon_name_rank = "species",
  family          = "Salmonidae",
  genus           = "Salmo",
  species         = "Salmo salar",
  stringsAsFactors = FALSE
)

# Step 1: add H2 (unreferenced Salmo sp.) + H3 (unreferenced genus in Salmonidae)
hyp_sp <- unreferenced_candidates(
  consensus_sp,
  rank_system = c("family", "genus", "species")
)

cat("Hypothesis types:\n")
print(table(hyp_sp$hypothesis_type))
stopifnot(
  nrow(hyp_sp) == 3L,
  "specific_candidate"   %in% hyp_sp$hypothesis_type,
  "unreferenced_species" %in% hyp_sp$hypothesis_type,
  "unreferenced_genus"   %in% hyp_sp$hypothesis_type
)

# Step 2: assign uniform likelihoods
lik_sp <- assign_scores(hyp_sp, score_type = "none")
cat("\nAll score_likelihood values:\n")
print(lik_sp$score_likelihood)
stopifnot(
  all(lik_sp$score_likelihood == 1.0),
  all(lik_sp$score_likelihood_mean == 1.0),
  all(lik_sp$score_likelihood_sd  == 0.0)
)
cat("PASS\n\n")

# ─────────────────────────────────────────────────────────────────────────────
cat("=== Demo 2: Multiple observations with mixed ranks ===\n")
cat("obs1 = species, obs2 = genus, obs3 = species from different family.\n\n")

consensus_mixed <- data.frame(
  observation_id  = c("obs1", "obs2", "obs3"),
  taxon_name      = c("Salmo salar", "Salvelinus", "Cyprinus carpio"),
  taxon_name_rank = c("species",     "genus",      "species"),
  family          = c("Salmonidae",  "Salmonidae",  "Cyprinidae"),
  genus           = c("Salmo",       "Salvelinus",  "Cyprinus"),
  species         = c("Salmo salar", NA_character_, "Cyprinus carpio"),
  stringsAsFactors = FALSE
)

hyp_mixed <- unreferenced_candidates(
  consensus_mixed,
  rank_system = c("family", "genus", "species")
)

cat("Candidate counts per observation:\n")
print(table(hyp_mixed$observation_id))
cat("(Each observation gets H1 + H2 + H3 = 3 rows)\n\n")
stopifnot(all(table(hyp_mixed$observation_id) == 3L))

lik_mixed <- assign_scores(hyp_mixed, score_type = "none")
stopifnot(all(lik_mixed$score_likelihood == 1.0))
cat("PASS\n\n")

# ─────────────────────────────────────────────────────────────────────────────
cat("=== Demo 3: include_unreferenced_family = TRUE ===\n")
cat("Adds a fourth catch-all row (NA taxon_name) per observation.\n")
cat("Use only when running WITHOUT TaxaExpect priors (e.g. LLM pathway).\n\n")

hyp_family <- unreferenced_candidates(
  consensus_sp,
  rank_system                 = c("family", "genus", "species"),
  include_unreferenced_family = TRUE
)

cat("Hypothesis types (should include unreferenced_family):\n")
print(table(hyp_family$hypothesis_type))
stopifnot(
  nrow(hyp_family) == 4L,
  "unreferenced_family" %in% hyp_family$hypothesis_type,
  sum(is.na(hyp_family$taxon_name)) == 1L
)

lik_family <- assign_scores(hyp_family, score_type = "none")
# With score_type = "none", ALL rows including unreferenced_family receive 1.0.
# The 0.05 fixed weight for unreferenced_family only applies for
# score_type = "probability" or "similarity_softmax".
cat("\nLikelihoods (score_type='none': all rows = 1.0 including unreferenced_family):\n")
print(lik_family[, c("taxon_name", "hypothesis_type", "score_likelihood")])
cat("PASS\n\n")

# ─────────────────────────────────────────────────────────────────────────────
cat("=== All demos passed ===\n")
cat("\nTo pass likelihoods to TaxaAssign:\n")
cat("  priors_joined <- TaxaAssign::join_priors(lik_sp, priors_df, main_habitat = ...)\n")
cat("  posteriors    <- TaxaAssign::compute_posterior(priors_joined, n_sims = 1000L)\n")
