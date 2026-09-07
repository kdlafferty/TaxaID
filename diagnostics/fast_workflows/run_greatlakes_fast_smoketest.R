# ==============================================================================
# run_greatlakes_fast_smoketest.R
# TaxaID -- Minutes-not-hours smoke test for the likelihood -> posterior ->
# consensus -> slash-taxon stage of the pipeline, against a real (curated,
# small) GreatLakes fixture built by build_fast_fixture.R.
#
# 2026-09-05: GreatLakes sibling of run_fast_smoketest.R (PtConception 12S).
# Same design and same caveats -- starts AFTER reference-quality screening
# (this checkpoint doesn't even carry those columns -- see the fixture build
# log, "reference_action"/"hierarchy_flag" not present) and stops before
# priors/review_assignments() for the same reasons documented there. Built
# specifically to guarantee Perca flavescens (Yellow Perch) coverage -- a
# taxon this ecosystem has repeatedly had to debug (walleye/perch resolution,
# see TaxaID/CLAUDE.md's 2026-08-20/26 entries) -- via
# always_include_taxa = "Perca flavescens" at fixture-build time.
# ==============================================================================

t0 <- Sys.time()

library(TaxaLikely)
library(TaxaAssign)

fixture_path   <- file.path("diagnostics", "fast_workflows", "greatlakes_fast_match_obj.rds")
lik_model_path <- file.path("diagnostics", "fast_workflows", "greatlakes_fast_lik_model_calibrated.rds")

stopifnot(file.exists(fixture_path), file.exists(lik_model_path))

match_obj <- readRDS(fixture_path)
lik_model <- readRDS(lik_model_path)

cat(sprintf("Fixture: %d observation(s), %d row(s)\n",
            length(unique(match_obj$observation_id)), nrow(match_obj)))
cat(sprintf("Perca flavescens rows in fixture: %d\n",
            sum(grepl("Perca flavescens", match_obj$taxon_name, ignore.case = TRUE))))

# --- Stage 1: score -> likelihood ---------------------------------------------
t1 <- Sys.time()
likelihoods <- TaxaLikely::evaluate_likelihoods(
  match_df     = match_obj,
  model_params = lik_model,
  n_sims       = 0L
)$likelihoods
cat(sprintf("evaluate_likelihoods(): %d row(s), %.1fs\n",
            nrow(likelihoods), as.numeric(Sys.time() - t1, units = "secs")))

# --- Stage 2: PLACEHOLDER prior (NOT real ecology) ----------------------------
# Same convention as the PtConception smoke test -- see its own header for the
# full warning. No real priors checkpoint was pulled for this fixture (would
# need a live GBIF/kernel-priors fit); this fixture targets pipeline-stage
# regression safety, not real ecological output.
likelihoods$prior_mean <- 0.5

# --- Stage 3: posterior -------------------------------------------------------
t3 <- Sys.time()
posterior_df <- TaxaAssign::compute_posterior(likelihoods, n_sims = 0)
cat(sprintf("compute_posterior(): %.1fs\n", as.numeric(Sys.time() - t3, units = "secs")))

# --- Stage 4: LCA consensus ----------------------------------------------------
t4 <- Sys.time()
# rank_system passed explicitly -- same reason as the PtConception smoke test:
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

cat("\n--- Perca flavescens observations (regression indicator for the walleye/perch resolution history) ---\n")
perca_obs_ids <- unique(match_obj$observation_id[grepl("Perca flavescens", match_obj$taxon_name, ignore.case = TRUE)])
print(slashed[slashed$observation_id %in% perca_obs_ids,
              c("observation_id", "consensus_taxon", "consensus_rank", "n_plausible", "irreducible_consensus")])
# EXPECTED under the flat 0.5 placeholder prior: consensus_taxon is NA for
# most/all of these -- Perca flavescens shares its posterior mass with several
# real congeners (Perca/Sander/Zingel/Niphon, all present as candidates) with
# nothing to discriminate them ecologically, so no candidate clears
# posterior_consensus()'s min_posterior threshold decisively. This is NOT a
# bug -- it is exactly the documented placeholder-prior limitation (see the
# "Notes on warnings" section below and run_fast_smoketest.R's own header).
# A real prior (occurrence-based, favoring the locally-established species)
# would be needed to see this resolve the way real GreatLakes production runs
# do (see TaxaID/CLAUDE.md's 2026-08-20/26 entries on yellow perch/walleye).

cat(sprintf("\nTotal wall time: %.1fs\n", as.numeric(Sys.time() - t0, units = "secs")))
