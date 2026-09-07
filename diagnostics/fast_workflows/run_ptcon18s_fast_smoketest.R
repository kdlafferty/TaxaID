# ==============================================================================
# run_ptcon18s_fast_smoketest.R
# TaxaID -- Minutes-not-hours smoke test for the likelihood -> prior -> posterior
# -> consensus -> slash-taxon stage of the pipeline, against a real (curated,
# small) PtConception 18S fixture built by build_fast_fixture.R.
#
# 2026-09-07: previously staged-but-blocked (see README.md's "PtConception 18S:
# staged, blocked" section) -- the live 18S production run has now completed
# through train_likelihood_model()/calibrate_query_noise() (and, in fact, the
# whole pipeline through review_assignments()), so a real
# PtCon18SSchulte_lik_model_calibrated.rds now exists. Copied here (checked
# stable, ~30+ hours old, not a live write) as
# ptcon18s_fast_lik_model_calibrated.rds.
#
# Differs from run_fast_smoketest.R/run_greatlakes_fast_smoketest.R in one
# structural way: this dataset already has a REAL taxaexpect_priors checkpoint
# (ptcon18s_fast_taxaexpect_priors.rds, staged 2026-09-05, kernel-priors output
# from a single-site kernel fit -- confirmed exactly 1 unique grid_id,
# "Site_34.40_-120.40"), so Stage 2 here is a real join_priors() call, not the
# flat 0.5 PLACEHOLDER the other two single-marker smoke tests need. Same
# Stage 1-5 numbering as its siblings for the same conceptual work throughout.
#
# join_priors() is called WITHOUT expansion_taxonomy/singleton_taxonomy (both
# optional, default NULL) -- omitting them means coarse-rank expansion and the
# habitat-agnostic fallback tier don't run, which only affects unmodelled/
# habitat-agnostic candidates, not the pipeline mechanics this smoke test
# targets (consensus/irreducibility/slash-taxon regression safety), matching
# the other two smoke tests' own precedent of simplifying what's not essential
# to the regression target rather than building every real production input.
# ==============================================================================

t0 <- Sys.time()

library(TaxaLikely)
library(TaxaAssign)

fixture_path      <- file.path("diagnostics", "fast_workflows", "ptcon18s_fast_match_obj.rds")
lik_model_path    <- file.path("diagnostics", "fast_workflows", "ptcon18s_fast_lik_model_calibrated.rds")
priors_path       <- file.path("diagnostics", "fast_workflows", "ptcon18s_fast_taxaexpect_priors.rds")

stopifnot(file.exists(fixture_path), file.exists(lik_model_path), file.exists(priors_path))

match_obj         <- readRDS(fixture_path)
lik_model         <- readRDS(lik_model_path)
taxaexpect_priors <- readRDS(priors_path)

cat(sprintf("Fixture: %d observation(s), %d row(s)\n",
            length(unique(match_obj$observation_id)), nrow(match_obj)))

# --- Stage 1: score -> likelihood ---------------------------------------------
t1 <- Sys.time()
likelihoods <- TaxaLikely::evaluate_likelihoods(
  match_df     = match_obj,
  model_params = lik_model,
  rank_system  = c("family", "genus", "species"),  # matches the real 18S
                                                     # production call
  n_sims       = 0L   # deterministic point estimates only -- fast, and
                       # sufficient for regression-testing consensus/
                       # irreducibility logic. Set n_sims > 0 to also
                       # smoke-test the Monte Carlo path if a change touches
                       # that instead.
)$likelihoods
cat(sprintf("evaluate_likelihoods(): %d row(s), %.1fs\n",
            nrow(likelihoods), as.numeric(Sys.time() - t1, units = "secs")))

# --- Stage 2: real priors (join_priors(), NOT a placeholder) ------------------
# taxaexpect_priors is real kernel-priors output from the live 18S run's Step 5
# (a single-site kernel fit -- exactly 1 unique grid_id by construction).
# Derived the SAME way the real production workflow derives its kernel-mode
# focal_grid (PtConceptionWorkflow_18S_2_single_site.R's own join_priors()
# call site): the single non-NA grid_id in taxaexpect_priors, no re-fitting.
t2 <- Sys.time()
focal_grid_ids <- unique(stats::na.omit(taxaexpect_priors$grid_id))
if (length(focal_grid_ids) != 1L) {
  warning(sprintf(
    "Expected exactly 1 distinct grid_id in this kernel-priors fixture, found %d -- using the most common one.",
    length(focal_grid_ids)
  ))
  focal_grid_ids <- taxaexpect_priors |>
    dplyr::filter(!is.na(grid_id)) |>
    dplyr::count(grid_id, sort = TRUE) |>
    dplyr::slice(1) |>
    dplyr::pull(grid_id)
}
site <- list(grid_id = focal_grid_ids, main_habitat = "Marine")
message(sprintf("  join_priors site grid: %s", site$grid_id))

likelihoods <- TaxaAssign::join_priors(
  likelihoods       = likelihoods,
  taxaexpect_priors = taxaexpect_priors,
  site              = site,
  rank_system       = c("order", "family", "genus", "species"),
  backbone_id       = 4L   # NCBI -- MATCH_BACKBONE_ID in the real 18S workflow
)
cat(sprintf("join_priors(): %d row(s), %.1fs\n",
            nrow(likelihoods), as.numeric(Sys.time() - t2, units = "secs")))

# --- Stage 3: posterior -------------------------------------------------------
t3 <- Sys.time()
posterior_df <- TaxaAssign::compute_posterior(likelihoods, n_sims = 0)
cat(sprintf("compute_posterior(): %.1fs\n", as.numeric(Sys.time() - t3, units = "secs")))

# --- Stage 4: LCA consensus ----------------------------------------------------
t4 <- Sys.time()
# rank_system passed explicitly -- same reason as the other two smoke tests:
# evaluate_likelihoods() only carries taxon_name/taxon_name_rank forward.
consensus <- TaxaAssign::posterior_consensus(posterior_df, rank_system = c("genus", "species"))
cat(sprintf("posterior_consensus(): %d observation(s), %.1fs\n",
            nrow(consensus), as.numeric(Sys.time() - t4, units = "secs")))

# --- Stage 5: slash-taxon + irreducibility -------------------------------------
t5 <- Sys.time()
slashed <- TaxaAssign::add_slash_taxon(consensus)
cat(sprintf("add_slash_taxon(): %.1fs\n", as.numeric(Sys.time() - t5, units = "secs")))

cat("\n--- irreducible_consensus (the 2026-09-04 order-invariance regression indicator) ---\n")
print(table(slashed$irreducible_consensus, useNA = "ifany"))

cat(sprintf("\nTotal wall time: %.1fs\n", as.numeric(Sys.time() - t0, units = "secs")))

# --- Notes -----------------------------------------------------------------
# Unlike the PtConception 12S / GreatLakes smoke tests, results here ARE
# meaningful (real trained model + real kernel priors), not just a pipeline-
# mechanics check -- though still a small, curated subset (200 observations),
# not the full real 18S consensus. No always_include_taxa guaranteed taxa were
# set when this fixture was built (README.md: "18S has no established
# problem-taxon precedent from past debugging yet") -- add one here (and
# rebuild the fixture) once a real 18S-specific debugging case exists, the
# same way Perca flavescens/Fundulus lima-parvipinnis were added for the other
# two sites.
