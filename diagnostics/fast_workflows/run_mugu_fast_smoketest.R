# ==============================================================================
# run_mugu_fast_smoketest.R
# TaxaID -- Minutes-not-hours smoke test for the posterior -> consensus ->
# slash-taxon stage of the pipeline, against a real (curated, small) Mugu
# 12S fixture built by build_fast_fixture.R.
#
# 2026-09-05: Mugu sibling of run_fast_smoketest.R (PtConception 12S) and
# run_greatlakes_fast_smoketest.R. Structurally different from both: Mugu's
# real production checkpoints (MuguWilderFish_blast_r1_12s.rds, a LIST with
# $posteriors/$consensus, not a flat match object) don't expose a single
# match-object-shaped source to re-run evaluate_likelihoods() from -- but
# $posteriors IS already a real, fully-computed posterior_df (real
# compute_posterior() output, complete with genuine kernel-priors-derived
# prior_mean/prior_alpha/prior_beta, NOT a placeholder). That makes this
# smoke test start one stage LATER than the other two (posterior_consensus()
# onward) but with GENUINELY REAL priors, not the flat 0.5 placeholder the
# PtConception/GreatLakes smoke tests need (no cached priors checkpoint
# exists for either of those datasets).
#
# Fixture built specifically to guarantee Fundulus lima vs. F. parvipinnis
# coverage -- the single most-debugged real Mugu edge case in this
# ecosystem's history (see e.g. TaxaID/CLAUDE.md's Session 158/159 entries) --
# via always_include_taxa at fixture-build time.
# ==============================================================================

t0 <- Sys.time()

library(TaxaAssign)

fixture_path <- file.path("diagnostics", "fast_workflows", "mugu12s_fast_posterior_df.rds")
stopifnot(file.exists(fixture_path))

posterior_df <- readRDS(fixture_path)

cat(sprintf("Fixture: %d observation(s), %d row(s)\n",
            length(unique(posterior_df$observation_id)), nrow(posterior_df)))
cat(sprintf("Fundulus lima/parvipinnis rows in fixture: %d\n",
            sum(grepl("Fundulus (lima|parvipinnis)", posterior_df$taxon_name, ignore.case = TRUE))))

# --- Stage 4: LCA consensus ----------------------------------------------------
# No rank_system override needed here (unlike the other two smoke tests) --
# this real posterior_df carries genus/family/order/class/phylum columns
# already (compute_posterior() preserves them; only evaluate_likelihoods()'s
# own output strips them), so posterior_consensus()'s auto-detection works.
t4 <- Sys.time()
consensus <- TaxaAssign::posterior_consensus(posterior_df)
cat(sprintf("posterior_consensus(): %d observation(s), %.1fs\n",
            nrow(consensus), as.numeric(Sys.time() - t4, units = "secs")))

# --- Stage 5: slash-taxon + irreducibility -------------------------------------
t5 <- Sys.time()
slashed <- TaxaAssign::add_slash_taxon(consensus)
cat(sprintf("add_slash_taxon(): %.1fs\n", as.numeric(Sys.time() - t5, units = "secs")))

cat("\n--- irreducible_consensus (the 2026-09-04 order-invariance regression indicator) ---\n")
print(table(slashed$irreducible_consensus, useNA = "ifany"))

cat("\n--- Fundulus lima / F. parvipinnis observations (the motivating real edge case) ---\n")
fundulus_obs_ids <- unique(posterior_df$observation_id[
  grepl("Fundulus (lima|parvipinnis)", posterior_df$taxon_name, ignore.case = TRUE)])
print(slashed[slashed$observation_id %in% fundulus_obs_ids,
              c("observation_id", "consensus_taxon", "consensus_rank", "consensus_posterior",
                "n_plausible", "irreducible_consensus")])
# EXPECTED, per this ecosystem's own documented history (restore_suppressed_
# candidates()/expand_unreferenced_hypotheses(), Sessions 158-159): these two
# species are genuinely hard to discriminate on 12S score alone -- a real
# resolution here (single winner vs. a slash/competing pair) depends on
# whether real occurrence priors + regional-overlap restoration correctly
# admitted BOTH as competing hypotheses upstream of this posterior_df, not on
# anything this smoke test's own stages (consensus/slash-taxon) do -- this
# test only confirms those stages handle whatever came in without erroring
# or silently dropping the observation (the exact 2026-09-04 regression
# class add_slash_taxon()'s order-invariance fix targets).

cat(sprintf("\nTotal wall time: %.1fs\n", as.numeric(Sys.time() - t0, units = "secs")))
