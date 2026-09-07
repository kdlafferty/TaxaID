# ==============================================================================
# run_fast_smoketest.R
# TaxaID -- Minutes-not-hours smoke test for the likelihood -> posterior ->
# consensus -> slash-taxon stage of the pipeline, against a real (curated,
# small) fixture built by build_fast_fixture.R.
#
# 2026-09-05: first cut of the "fast test workflow" the user asked for. This
# is deliberately narrower than a full production workflow -- it starts
# AFTER reference-quality screening (already baked into the fixture) and
# STOPS before priors/review_assignments(), because:
#   - no cached real priors (TaxaExpect kernel/GLMM output) checkpoint exists
#     for this dataset yet (checked 2026-09-05 -- see the CLAUDE.md note this
#     script's own header points at). A real prior build needs a live GBIF
#     fetch, which defeats the point of a FAST test.
#   - review_assignments() makes real, billed LLM calls -- never something
#     to run automatically inside a smoke test.
#
# What IS exercised here, on real data, in well under a minute:
#   evaluate_likelihoods() -> a PLACEHOLDER uniform prior (NOT real ecology --
#   see the loud warning below) -> compute_posterior() -> posterior_consensus()
#   -> add_slash_taxon(). This is exactly the stage where the 2026-09-04
#   order-invariance irreducibility bug lived (TaxaAssign::add_slash_taxon()),
#   so this script's own output (irreducible_consensus counts) is a
#   reasonable regression indicator for that class of bug even without real
#   priors.
#
# To extend this to a genuine end-to-end fast test (real priors, real
# review_assignments()), see the "Extending this" section at the bottom.
# ==============================================================================

t0 <- Sys.time()

# Run from the TaxaID project root (relative paths below assume this).
library(TaxaLikely)
library(TaxaAssign)

fixture_path   <- file.path("diagnostics", "fast_workflows", "ptcon12s_fast_match_obj.rds")
lik_model_path <- file.path("diagnostics", "fast_workflows", "ptcon12s_fast_lik_model_calibrated.rds")

stopifnot(file.exists(fixture_path), file.exists(lik_model_path))

match_obj <- readRDS(fixture_path)
lik_model <- readRDS(lik_model_path)

cat(sprintf("Fixture: %d observation(s), %d row(s)\n",
            length(unique(match_obj$observation_id)), nrow(match_obj)))

# --- Stage 1: score -> likelihood ---------------------------------------------
t1 <- Sys.time()
likelihoods <- TaxaLikely::evaluate_likelihoods(
  match_df     = match_obj,
  model_params = lik_model,
  n_sims       = 0L   # deterministic point estimates only -- fast, and
                       # sufficient for regression-testing consensus/
                       # irreducibility logic, which is what this fixture
                       # targets. Set n_sims > 0 to also smoke-test the
                       # Monte Carlo path if a change touches that instead.
)$likelihoods
cat(sprintf("evaluate_likelihoods(): %d row(s), %.1fs\n",
            nrow(likelihoods), as.numeric(Sys.time() - t1, units = "secs")))

# --- Stage 2: PLACEHOLDER prior (NOT real ecology) ----------------------------
# ****************************************************************************
# * WARNING: prior_mean is a flat 0.5 for every candidate, every observation. *
# * This is a smoke-test convenience so compute_posterior()'s Beta-sampling  *
# * path has valid input -- it says nothing about real occurrence/habitat    *
# * plausibility. NEVER read the resulting posterior_mean/consensus_taxon as *
# * a real result. Its only legitimate use is checking that the LATER       *
# * pipeline stages (posterior computation, LCA consensus, irreducibility,  *
# * slash-taxon labeling) run without erroring and without the specific     *
# * order-invariance-style bug class this fixture targets.                  *
# ****************************************************************************
likelihoods$prior_mean <- 0.5

# --- Stage 3: posterior -------------------------------------------------------
t3 <- Sys.time()
posterior_df <- TaxaAssign::compute_posterior(likelihoods, n_sims = 0)
cat(sprintf("compute_posterior(): %.1fs\n", as.numeric(Sys.time() - t3, units = "secs")))

# --- Stage 4: LCA consensus ----------------------------------------------------
t4 <- Sys.time()
# rank_system passed explicitly: evaluate_likelihoods()'s output only carries
# taxon_name/taxon_name_rank forward (documented contract -- kingdom..species
# columns are NOT preserved), and posterior_consensus()'s auto-detection does
# not gracefully handle a zero-rank-columns input (errors deep inside
# .find_lca() with "subscript out of bounds" rather than falling back to the
# genus/species-from-binomial derivation its own docs describe -- found
# 2026-09-05 running this exact script; worth a look in the critical-review
# pass, not fixed here). Real single-marker workflows hit this identically
# and already pass rank_system explicitly for the same reason.
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

# --- Notes on warnings you'll see running this (both expected, both real) ----
# 1. "no hypotheses above min_posterior" on a handful of observations: an
#    artifact of the flat 0.5 PLACEHOLDER prior spread thin across
#    observations with many (24-69) named candidates -- expected here, would
#    be a real signal with real priors.
# 2. add_slash_taxon()'s "do not look like plausible species binomials"
#    warning (genus-only names like "Pan"/"Gibbonsia"/"Oligocottus" reaching
#    slash-name formatting) is NOT a placeholder-prior artifact -- it fires
#    on real production data regardless of the prior used. Worth a look in
#    the critical-review pass: are genus-level fallback hypotheses reaching
#    a function whose own docs warn this can corrupt formatting?

# --- Extending this to a full end-to-end fast test ----------------------------
# 1. Real priors: build a small TaxaExpect::generate_full_priors()-shaped
#    object for just the taxa present in `match_obj` (union of taxon_name
#    across the fixture -- a few dozen species, not the full regional list),
#    against the SAME small set of grid cells the fixture's observations
#    actually fall in. This still needs one real (but narrowly-scoped) GBIF
#    fetch -- cache its result the same way build_fast_fixture.R caches the
#    match object, so it's a one-time cost, not a per-run one.
# 2. join_priors() the real priors onto `likelihoods` in place of the flat
#    0.5 placeholder above, then re-run Stages 3-5 -- results become
#    meaningful, not just regression-safe.
# 3. review_assignments(): call it explicitly, deliberately, when you want to
#    smoke-test that stage too -- never wire it into an unattended script,
#    since it is a real, billed LLM call every time it runs.
