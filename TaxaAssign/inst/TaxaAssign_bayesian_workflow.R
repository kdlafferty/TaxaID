# TaxaAssign: Full Bayesian Workflow (non-LLM pipeline)
# ============================================================================
#
# Non-LLM counterpart to TaxaAssign_llm_workflow.R.
# Combines score-based likelihoods (TaxaLikely) with occurrence-based priors
# (TaxaExpect) using a formal Bayesian update.
#
# Parallel structure to the LLM workflow:
#   LLM workflow     -- assign_taxa_llm() generates both likelihoods and priors
#   Bayesian workflow -- TaxaLikely and TaxaExpect supply them independently
#
# When to use this workflow vs. the LLM workflow:
#   Bayesian -- preferred when you have a well-trained TaxaLikely model and
#               TaxaExpect priors; fully reproducible; no API costs
#   LLM      -- preferred for rapid exploration, novel taxa, or when reference
#               training data are sparse
#
# Prerequisites (run these first in their respective packages):
#   TaxaMatch:   standardize_match_data()  -> match_obj
#   TaxaLikely:  train_likelihood_model()  -> model_params  (see TaxaLikely_workflow.R)
#   TaxaFetch:   fetch occurrence data
#   TaxaHabitat: assign_habitat_*()
#   TaxaExpect:  generate_full_priors()    -> taxaexpect_priors
#
# Requires: TaxaLikely, TaxaAssign (this package), TaxaMatch, dplyr
# ============================================================================

library(TaxaLikely)
library(TaxaAssign)
library(TaxaMatch)   # filter_redundant_hypotheses()
library(dplyr)

# ---- Runtime tracking --------------------------------------------------------
.timings <- list()
.tic <- function(label) { .timings[[label]] <<- proc.time() }
.toc <- function(label) {
  elapsed <- (proc.time() - .timings[[label]])[["elapsed"]]
  .timings[[label]] <<- elapsed
  cat(sprintf("  [%s] %.2f sec\n", label, elapsed))
  elapsed
}

# =============================================================================
# SECTION 1: LOAD INPUTS
# =============================================================================
# Three pre-computed objects:
#   match_obj         — from TaxaMatch (raw match data)
#   lik_result        — from TaxaLikely::evaluate_likelihoods()
#   taxaexpect_priors — from TaxaExpect::generate_full_priors()

match_obj  <- readRDS(file.choose())  # select match_obj.rds from TaxaMatch/inst/
lik_result <- readRDS(file.choose())  # select real_likelihoods.rds from TaxaLikely/inst/
taxaexpect_priors <- readRDS(file.choose())  # select taxaexpect_priors.rds from TaxaExpect/inst/

match_obj  <-match_obj[1:20,]

cat("Likelihood rows:", nrow(lik_result$likelihoods), "\n")
if (nrow(lik_result$unresolved) > 0L) {
  cat("Unresolved observation_ids:", n_distinct(lik_result$unresolved$observation_id), "\n")
  # Optional: re-run at family level
  # lik_family <- TaxaLikely::evaluate_likelihoods(
  #   match_df = lik_result$unresolved, model_params = model_params,
  #   rank_system = c("order", "family"), n_sims = 200L
  # )
  # lik_result$likelihoods <- bind_rows(lik_result$likelihoods, lik_family$likelihoods)
}

# Keep finest-rank specific candidates per query
.tic("S1_filter_top")
top_likelihoods <- TaxaLikely::filter_top_hypotheses(
  lik_result$likelihoods,
  rank_system = c("family", "genus", "species")
)
.toc("S1_filter_top")
cat("Top-hypothesis rows:", nrow(top_likelihoods), "\n")

# Extract plausible species from TaxaExpect (used in Sections 2 and 4)
taxaexpect_species_df <- taxaexpect_priors |>
  select(taxon_name, genus, family) |>
  distinct() |>
  filter(!is.na(taxon_name))

cat("TaxaExpect plausible species:", nrow(taxaexpect_species_df), "\n")


# =============================================================================
# SECTION 2: UNREFERENCED EXPANSION + COVERAGE CONSTRAINTS
# =============================================================================
# Identifies species that TaxaExpect considers plausible but that have no
# barcode reference sequence. Replaces generic H2/H3 rows with named species,
# then suppresses unreferenced_species for fully-covered genera.
#
# Order matters: expand BEFORE apply_coverage_constraints().

# ---- 2a. Identify unreferenced species via NCBI barcode audit ---------------
reference_species_df <- match_obj[!duplicated(match_obj$species),
                                   c("genus", "species")]

.tic("S2a_audit_coverage")
coverage <- TaxaLikely::audit_barcode_coverage(
  match_df     = reference_species_df,
  barcode_term = "12S",
  species_list = taxaexpect_species_df$taxon_name,
  target_rank  = "genus"
  # max_date   = "2024/12/31"
)
.toc("S2a_audit_coverage")
cat("\nCoverage census:\n"); print(coverage$census)
cat("\nUnreferenced species:\n"); print(coverage$unreferenced)

# ---- 2b. Expand generic H2/H3 rows into named species -----------------------
unreferenced_df <- taxaexpect_species_df |>
  filter(taxon_name %in% coverage$unreferenced) |>
  rename(species = taxon_name)

cat("Unreferenced species with TaxaExpect priors:", nrow(unreferenced_df), "\n")

.tic("S2b_expand")
expanded_likelihoods <- expand_unreferenced_hypotheses(
  likelihood_df   = top_likelihoods,
  unreferenced_df = unreferenced_df
)
.toc("S2b_expand")
cat("Expanded likelihood rows:", nrow(expanded_likelihoods), "\n")

# ---- 2c. Apply coverage constraints -----------------------------------------
census_result <- mutate(
  coverage$census,
  taxon_name = group, rank = "genus",
  status = ifelse(is_complete, "complete", "incomplete")
)

.tic("S2c_constraints")
final_likelihoods <- TaxaLikely::apply_coverage_constraints(
  expanded_likelihoods, census_result, constraint_behavior = "relabel"
)
.toc("S2c_constraints")
cat("Rows with coverage constraints applied:",
    sum(!is.na(final_likelihoods$constraint_applied)), "\n")


# =============================================================================
# SECTION 3: DEFINE SITE CONTEXT + JOIN PRIORS
# =============================================================================
# The new join_priors() function handles everything between "I have likelihoods"
# and "I'm ready for compute_posterior()":
#   - Maps observation_ids to grid_id + main_habitat
#   - Joins to taxaexpect_priors (with dark diversity fallback for unmatched species)
#   - Deduplicates + fills taxonomy + filters redundant hypotheses
#
# --- Site context ---
# For the common single-site case, pass a named list:
site <- list(grid_id = "Grid_34p1_m119p1", main_habitat = "Estuarine Bay")
#
# For multi-site, pass a data frame with one row per observation_id:
# site <- data.frame(
#   observation_id    = c("ESV_001", "ESV_002", "ESV_003"),
#   grid_id      = c("Grid_34p1_m119p1", "Grid_34p1_m119p1", "Grid_33p7_m118p2"),
#   main_habitat = c("Estuarine Bay", "Estuarine Bay", "Sandy Beach")
# )

taxonomy_lookup <- match_obj |>
  dplyr::select(taxon_name, order, family, genus, species) |>
  dplyr::distinct(taxon_name, .keep_all = TRUE)

.tic("S3_join_priors")
likelihoods_ready <- join_priors(
  likelihoods       = final_likelihoods,
  taxaexpect_priors = taxaexpect_priors,
  site              = site,
  taxonomy_lookup   = taxonomy_lookup,
  rank_system       = c("order", "family", "genus", "species")
)
.toc("S3_join_priors")
cat("Rows ready for posterior:", nrow(likelihoods_ready), "\n")


# =============================================================================
# SECTION 4: COMPUTE POSTERIOR
# =============================================================================
.tic("S4_posterior")
posteriors <- compute_posterior(likelihoods_ready, n_sims = 1000L)
.toc("S4_posterior")

cat("\nPosterior rows:", nrow(posteriors), "\n")
cat("Unique observation_ids:", n_distinct(posteriors$observation_id), "\n")


# =============================================================================
# SECTION 5: CONSENSUS TAXONOMY + EMPIRICAL BAYES REFINEMENT
# =============================================================================
.tic("S5_consensus")
consensus <- posterior_consensus(
  posteriors,
  cumulative_threshold    = 0.90,
  min_posterior            = 0.05,
  posterior_col            = "posterior_point_est",
  lookup_missing_taxonomy  = TRUE,
  backbone_id              = 4,
  rank_system              = c("order", "family", "genus", "species"),
  species_reference        = taxaexpect_species_df
)

posteriors_updated <- update_prior_from_consensus(
  posteriors, consensus,
  presence_multiplier = 5,
  n_sims              = 1000
)

consensus_final <- posterior_consensus(
  posteriors_updated,
  cumulative_threshold    = 0.90,
  min_posterior            = 0.05,
  posterior_col            = "posterior_point_est",
  lookup_missing_taxonomy  = TRUE,
  backbone_id              = 4,
  rank_system              = c("order", "family", "genus", "species"),
  species_reference        = taxaexpect_species_df
)
.toc("S5_consensus")

cat("\nConsensus taxonomy summary:\n")
print(table(consensus_final$consensus_rank, useNA = "always"))
cat("\nResolved to species-level:",
    sum(consensus_final$is_resolved, na.rm = TRUE), "/",
    nrow(consensus_final), "samples\n")

consensus_final


# =============================================================================
# SECTION 6: SCORE-BASED CONSENSUS (CONVENTIONAL APPROACH)
# =============================================================================
# Conventional metabarcoding consensus for comparison with the Bayesian
# posterior_consensus() above.  Works directly from raw match scores — no
# trained model, no priors.
#
# Uses the match_df loaded in Section 1 (before likelihood modelling).
# Thresholds follow common eDNA conventions (GITA pipeline / Jonah Ventures):
#   species >= 98%, genus >= 95%, family >= 90%, order >= 85%
#
# max_gap = 1: all hits within 1% of the top score contribute to the LCA.

score_con <- score_consensus(
  match_df        = match_obj,
  min_score       = 80,
  max_gap         = 1,
  rank_thresholds = c(species = 98, genus = 95, family = 90, order = 85),
  whitelist       = NULL,
  score_col       = "score_original",
  rank_system     = c("family", "genus", "species")
)

cat("\nScore-based consensus summary:\n")
print(table(score_con$consensus_rank, useNA = "always"))
cat("Resolved to species-level:",
    sum(score_con$is_resolved, na.rm = TRUE), "/",
    nrow(score_con), "samples\n")


# =============================================================================
# SECTION 7: COMPARE POSTERIOR vs SCORE-BASED CONSENSUS
# =============================================================================
comparison <- merge(
  consensus_final[, c("observation_id", "consensus_taxon", "consensus_rank",
                       "is_resolved", "consensus_posterior", "n_plausible")],
  score_con[, c("observation_id", "consensus_taxon", "consensus_rank",
                 "is_resolved", "top_score", "n_taxa")],
  by = "observation_id", suffixes = c("_posterior", "_score")
)

comparison$taxon_agree <- comparison$consensus_taxon_posterior ==
                          comparison$consensus_taxon_score
comparison$rank_agree  <- comparison$consensus_rank_posterior ==
                          comparison$consensus_rank_score
comparison$taxon_agree[is.na(comparison$consensus_taxon_posterior) |
                       is.na(comparison$consensus_taxon_score)] <- FALSE
comparison$rank_agree[is.na(comparison$consensus_rank_posterior) |
                      is.na(comparison$consensus_rank_score)] <- FALSE

cat("\n--- Posterior vs Score Consensus Comparison ---\n")
cat("Total samples:", nrow(comparison), "\n")
cat("Taxon agreement:", sum(comparison$taxon_agree), "/", nrow(comparison),
    sprintf("(%.0f%%)\n", 100 * mean(comparison$taxon_agree)))
cat("Rank agreement: ", sum(comparison$rank_agree), "/", nrow(comparison),
    sprintf("(%.0f%%)\n", 100 * mean(comparison$rank_agree)))

cat("\nResolution comparison (rows = posterior, cols = score):\n")
res_table <- table(
  posterior = ifelse(is.na(comparison$consensus_rank_posterior), "unresolvable",
                     comparison$consensus_rank_posterior),
  score    = ifelse(is.na(comparison$consensus_rank_score), "unresolvable",
                     comparison$consensus_rank_score)
)
print(res_table)

disagree <- comparison[!comparison$taxon_agree, ]
if (nrow(disagree) > 0L) {
  cat("\nDisagreements (", nrow(disagree), " samples):\n")
  print(disagree[, c("observation_id",
                      "consensus_taxon_posterior", "consensus_rank_posterior",
                      "consensus_taxon_score", "consensus_rank_score",
                      "consensus_posterior", "top_score")])
}

posterior_finer <- comparison[
  !is.na(comparison$consensus_rank_posterior) &
  !is.na(comparison$consensus_rank_score) &
  match(comparison$consensus_rank_posterior,
        c("family", "genus", "species")) >
  match(comparison$consensus_rank_score,
        c("family", "genus", "species")), ]
cat("\nPosterior resolved finer than score:", nrow(posterior_finer), "samples\n")

score_finer <- comparison[
  !is.na(comparison$consensus_rank_posterior) &
  !is.na(comparison$consensus_rank_score) &
  match(comparison$consensus_rank_score,
        c("family", "genus", "species")) >
  match(comparison$consensus_rank_posterior,
        c("family", "genus", "species")), ]
cat("Score resolved finer than posterior:", nrow(score_finer), "samples\n")


# =============================================================================
# TIMING SUMMARY
# =============================================================================
.timing_df <- data.frame(
  step    = names(.timings),
  seconds = unlist(.timings),
  stringsAsFactors = FALSE
)
.timing_df$pct <- round(100 * .timing_df$seconds / sum(.timing_df$seconds), 1)
cat("\n--- Timing Summary ---\n")
print(.timing_df, row.names = FALSE)
cat(sprintf("Total: %.2f sec\n", sum(.timing_df$seconds)))

# Save key outputs for comparison with optimized workflow
.baseline_outputs <- list(
  consensus_final  = consensus_final,
  posteriors       = posteriors_updated,
  likelihoods      = final_likelihoods,
  timings          = .timing_df
)


# =============================================================================
# ASSEMBLED REPORT (Distributed Report Architecture)
# =============================================================================
# The Bayesian workflow touches more packages, so the assembled report is richer.
# Each section is generated from the objects already computed above.

library(TaxaFetch)
library(TaxaMatch)
library(TaxaLikely)
library(TaxaHabitat)
library(TaxaExpect)

# Per-package report sections (include whichever are available):

# match_sec <- TaxaMatch::report_match(match_df, data_type = "eDNA")

likelihood_sec <- TaxaLikely::report_likelihood(real_model)

# If occurrences are available (from TaxaFetch/build_priors):
# fetch_sec <- TaxaFetch::report_fetch(occurrences, study_area = "Santa Barbara Channel")

# If priors came from build_priors():
# priors_sec <- TaxaExpect::report_priors(bp_output)

# If habitat weights are available:
# habitat_sec <- TaxaHabitat::report_habitat(habitat_weights)

# Assignment section:
assign_sec <- TaxaAssign::report_assign(posteriors_updated, consensus_final, data_type = "eDNA")

# Assemble all available sections:
assembled <- TaxaTools::assemble_report(
  likelihood_sec, assign_sec,
  title = "eDNA Taxonomic Assignment — Bayesian Workflow"
)
cat(assembled)
