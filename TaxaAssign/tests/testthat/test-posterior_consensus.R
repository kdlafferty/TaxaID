# test-posterior_consensus.R

# ==============================================================================
# Helpers
# ==============================================================================

make_posterior <- function(observation_id, taxon_name, taxon_name_rank,
                            hypothesis_type, posterior_mean,
                            genus = NULL, family = NULL, species = NULL) {
  df <- data.frame(
    observation_id       = observation_id,
    taxon_name      = taxon_name,
    taxon_name_rank = taxon_name_rank,
    hypothesis_type = hypothesis_type,
    posterior_mean  = posterior_mean,
    # mirrored so fixtures exercise the (2026-08-28) default
    # posterior_col = "posterior_point_est" without each test opting in
    posterior_point_est = posterior_mean,
    stringsAsFactors = FALSE
  )
  if (!is.null(genus))   df$genus   <- genus
  if (!is.null(family))  df$family  <- family
  if (!is.null(species)) df$species <- species
  df
}


# ==============================================================================
# Basic structure
# ==============================================================================

test_that("returns one row per observation_id", {
  df <- make_posterior(
    observation_id       = c("s1", "s1", "s2"),
    taxon_name      = c("Fundulus parvipinnis", "Fundulus catus", "Gobiosoma bosc"),
    taxon_name_rank = c("species", "species", "species"),
    hypothesis_type = rep("specific_candidate", 3),
    posterior_mean  = c(0.6, 0.4, 1.0)
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_equal(nrow(out), 2L)
  expect_equal(sort(out$observation_id), c("s1", "s2"))
})

test_that("output has required columns", {
  df <- make_posterior("s1", "Fundulus parvipinnis", "species",
                        "specific_candidate", 1.0)
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_true(all(c("observation_id", "consensus_taxon", "consensus_rank",
                    "is_resolved", "n_plausible",
                    "plausible_taxa", "plausible_posteriors") %in% names(out)))
})


# ==============================================================================
# Single-hypothesis samples
# ==============================================================================

test_that("single unambiguous species resolves to species", {
  df <- make_posterior("s1", "Fundulus parvipinnis", "species",
                        "specific_candidate", 0.95)
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_equal(out$consensus_taxon, "Fundulus parvipinnis")
  expect_equal(out$consensus_rank,  "species")
  expect_true(out$is_resolved)
  expect_equal(out$n_plausible, 1L)
})

test_that("single genus-rank hypothesis resolves at genus", {
  df <- make_posterior("s1", "Fundulus", "genus",
                        "specific_candidate", 0.9)
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_equal(out$consensus_taxon, "Fundulus")
  expect_equal(out$consensus_rank,  "genus")
  expect_false(out$is_resolved)  # genus is not the finest rank (species is)
})


# ==============================================================================
# consensus_posterior computation (Session 152 bug fix)
# ==============================================================================
# .extract_rank_values() had a genus-from-binomial fallback but no equivalent
# species-from-taxon_name fallback -- so whenever the input had no explicit
# "species" column (TaxaLikely's real sequence/BLAST pathway never produces
# one), consensus_posterior/consensus_confidence_score silently computed to
# exactly 0 for a single-hypothesis resolved observation, even though the
# winning candidate's own posterior_mean was correctly high. consensus_taxon
# itself was unaffected (a different code path), which is why no existing
# test here (none of which asserted on consensus_posterior's VALUE before
# this section) caught it.

test_that("consensus_posterior reflects the winner's posterior_mean, not 0, with no explicit species column", {
  df <- make_posterior(
    observation_id  = c("s1", "s1", "s1"),
    taxon_name      = c("Oligocottus snyderi", "Leiocottus hirundo", "Oligocottus maculosus"),
    taxon_name_rank = rep("species", 3),
    hypothesis_type = rep("specific_candidate", 3),
    posterior_mean  = c(0.9993, 0.0004, 0.0003)
  )
  expect_false("species" %in% names(df))
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_taxon, "Oligocottus snyderi")
  expect_equal(out$consensus_reason, "single")
  expect_equal(out$consensus_posterior, 0.9993, tolerance = 1e-6)
  expect_true(out$consensus_posterior > 0.5)
})

test_that("consensus_posterior sums only the winning LCA taxon's mass across all named hypotheses", {
  # Two candidates, winner clears cumulative_threshold alone (single plausible),
  # but named_all (pre-filter) still has both -- consensus_posterior must equal
  # just the winner's own posterior_mean, not the sum of both.
  df <- make_posterior(
    observation_id  = c("s1", "s1"),
    taxon_name      = c("Embiotoca jacksoni", "Phanerodon furcatus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean  = c(0.9385, 0.0615)
  )
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_taxon, "Embiotoca jacksoni")
  expect_equal(out$consensus_posterior, 0.9385, tolerance = 1e-6)
})


# ==============================================================================
# LCA logic
# ==============================================================================

test_that("two species in same genus → LCA at genus (derived from binomial)", {
  df <- make_posterior(
    observation_id       = c("s1", "s1"),
    taxon_name      = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = c("species", "species"),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean  = c(0.55, 0.45)
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_equal(out$consensus_taxon, "Fundulus")
  expect_equal(out$consensus_rank,  "genus")
  expect_false(out$is_resolved)
})

test_that("two species in different genera → LCA at family (explicit column)", {
  df <- make_posterior(
    observation_id       = c("s1", "s1"),
    taxon_name      = c("Fundulus parvipinnis", "Gobiosoma bosc"),
    taxon_name_rank = c("species", "species"),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean  = c(0.55, 0.45),
    family          = c("Fundulidae", "Gobiidae")
  )
  # Same family → LCA = family
  df$family <- c("Gobiidae", "Gobiidae")  # force same family
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_rank, "family")
  expect_false(out$is_resolved)
})

test_that("species in different families with no shared rank → NA", {
  df <- make_posterior(
    observation_id       = c("s1", "s1"),
    taxon_name      = c("Fundulus parvipinnis", "Gobiosoma bosc"),
    taxon_name_rank = c("species", "species"),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean  = c(0.55, 0.45),
    family          = c("Fundulidae", "Gobiidae")
  )
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_true(is.na(out$consensus_taxon))
  expect_true(is.na(out$consensus_rank))
})


# ==============================================================================
# Cumulative threshold
# ==============================================================================

test_that("cumulative_threshold limits included hypotheses", {
  # First species alone accounts for 0.91 of named mass → only 1 included
  df <- make_posterior(
    observation_id       = c("s1", "s1", "s1"),
    taxon_name      = c("Fundulus parvipinnis", "Fundulus catus", "Fundulus nottii"),
    taxon_name_rank = rep("species", 3),
    hypothesis_type = rep("specific_candidate", 3),
    posterior_mean  = c(0.91, 0.05, 0.04)
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"),
                              cumulative_threshold = 0.9)
  expect_equal(out$n_plausible, 1L)
  expect_equal(out$consensus_taxon, "Fundulus parvipinnis")
  expect_true(out$is_resolved)
})

test_that("lower cumulative_threshold can resolve to species from two-way tie", {
  df <- make_posterior(
    observation_id       = c("s1", "s1"),
    taxon_name      = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean  = c(0.8, 0.2)
  )
  # With threshold 0.75, only the top species (0.8/1.0 = 80% ≥ 75%) is included
  out <- posterior_consensus(df, rank_system = c("genus", "species"),
                              cumulative_threshold = 0.75)
  expect_equal(out$n_plausible, 1L)
  expect_equal(out$consensus_taxon, "Fundulus parvipinnis")
})


# ==============================================================================
# min_posterior filter
# ==============================================================================

test_that("hypotheses below min_posterior are excluded before LCA", {
  # Second species is 0.03 < 0.05 → excluded → single species resolves
  df <- make_posterior(
    observation_id       = c("s1", "s1"),
    taxon_name      = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean  = c(0.97, 0.03)
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"),
                              min_posterior = 0.05)
  expect_equal(out$n_plausible, 1L)
  expect_equal(out$consensus_taxon, "Fundulus parvipinnis")
})

test_that("all hypotheses below min_posterior → empty row", {
  df <- make_posterior(
    observation_id       = c("s1", "s1"),
    taxon_name      = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean  = c(0.04, 0.03)
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"),
                              min_posterior = 0.05)
  expect_equal(out$n_plausible, 0L)
  expect_true(is.na(out$consensus_taxon))
  expect_false(out$is_resolved)
})


# ==============================================================================
# Hypothesis type filtering
# ==============================================================================

test_that("unreferenced_family rows are excluded from LCA", {
  df <- rbind(
    make_posterior("s1", "Fundulus parvipinnis", "species",
                    "specific_candidate", 0.6),
    make_posterior("s1", NA_character_, NA_character_,
                    "unreferenced_family", 0.4)
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  # Only Fundulus parvipinnis contributes → single species resolved
  expect_equal(out$n_plausible, 1L)
  expect_equal(out$consensus_taxon, "Fundulus parvipinnis")
  expect_true(out$is_resolved)
})

test_that("unreferenced_genus named species are included in LCA", {
  # Family-level unreferenced taxon: species from a genus absent in the reference.
  # Should widen LCA just like unreferenced_species.
  df <- rbind(
    make_posterior("s1", "Fundulus parvipinnis", "species",
                    "specific_candidate", 0.7),
    make_posterior("s1", "Hesperoleucus symmetricus", "species",
                    "unreferenced_genus", 0.3)
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  # Different genera → LCA cannot resolve at genus → NA (no shared family column)
  expect_equal(out$n_plausible, 2L)
})

test_that("unreferenced_genus family-level unreferenced taxa resolve at family when column present", {
  df <- rbind(
    make_posterior("s1", "Fundulus parvipinnis", "species",
                    "specific_candidate", 0.7,
                    family = "Leuciscidae"),
    make_posterior("s1", "Hesperoleucus symmetricus", "species",
                    "unreferenced_genus", 0.3,
                    family = "Leuciscidae")
  )
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_rank, "family")
  expect_equal(out$consensus_taxon, "Leuciscidae")
  expect_equal(out$n_plausible, 2L)
})

test_that("unreferenced_species rows are included in LCA", {
  df <- rbind(
    make_posterior("s1", "Fundulus parvipinnis", "species",
                    "specific_candidate", 0.55),
    make_posterior("s1", "Fundulus sp_unref", "species",
                    "unreferenced_species", 0.45)
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  # Both are Fundulus → LCA at genus
  expect_equal(out$consensus_rank, "genus")
  expect_equal(out$consensus_taxon, "Fundulus")
  expect_equal(out$n_plausible, 2L)
})


# ==============================================================================
# No named hypotheses → empty row
# ==============================================================================

test_that("sample with only unreferenced_family → empty row", {
  df <- make_posterior("s1", NA_character_, NA_character_,
                        "unreferenced_family", 1.0)
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_equal(out$n_plausible, 0L)
  expect_true(is.na(out$consensus_taxon))
  expect_false(out$is_resolved)
  expect_equal(length(out$plausible_taxa[[1]]), 0L)
})


# ==============================================================================
# List column contents
# ==============================================================================

test_that("plausible_taxa and plausible_posteriors have correct content", {
  df <- make_posterior(
    observation_id       = c("s1", "s1"),
    taxon_name      = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean  = c(0.7, 0.3)
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"),
                              cumulative_threshold = 1.0)
  taxa <- out$plausible_taxa[[1]]
  posts <- out$plausible_posteriors[[1]]
  expect_equal(taxa[1], "Fundulus parvipinnis")   # sorted descending
  expect_equal(taxa[2], "Fundulus catus")
  expect_named(posts)
  expect_equal(posts[["Fundulus parvipinnis"]], 0.7)
  expect_equal(posts[["Fundulus catus"]], 0.3)
})


# ==============================================================================
# Explicit taxonomy columns
# ==============================================================================

test_that("explicit genus column takes precedence over binomial derivation", {
  df <- make_posterior(
    observation_id       = c("s1", "s1"),
    taxon_name      = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean  = c(0.55, 0.45),
    genus           = c("Fundulus", "Fundulus")
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_equal(out$consensus_taxon, "Fundulus")
  expect_equal(out$consensus_rank, "genus")
})


# ==============================================================================
# Input validation
# ==============================================================================

# ==============================================================================
# winner_prior / winner_likelihood / winner_likelihood_cov
# ==============================================================================

test_that("winner columns present and NA when source columns absent", {
  df <- make_posterior("s1", "Fundulus parvipinnis", "species",
                        "specific_candidate", 0.9)
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_true(all(c("winner_prior", "winner_likelihood",
                    "winner_likelihood_cov") %in% names(out)))
  expect_true(is.na(out$winner_prior))
  expect_true(is.na(out$winner_likelihood))
  expect_true(is.na(out$winner_likelihood_cov))
})

test_that("winner columns carry values from highest-posterior row", {
  df <- make_posterior(
    observation_id  = c("s1", "s1"),
    taxon_name      = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean  = c(0.7, 0.3)
  )
  df$prior_mean           <- c(0.12, 0.05)
  df$score_likelihood     <- c(0.88, 0.60)
  df$score_likelihood_cov <- c(0.80, 0.55)

  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  # Winner is Fundulus parvipinnis (posterior_mean = 0.7)
  expect_equal(out$winner_prior,          0.12)
  expect_equal(out$winner_likelihood,     0.88)
  expect_equal(out$winner_likelihood_cov, 0.80)
})

test_that("winner columns reflect actual winner, not highest likelihood", {
  # Ensure the winner is determined by posterior, not by likelihood
  df <- make_posterior(
    observation_id  = c("s1", "s1"),
    taxon_name      = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean  = c(0.3, 0.7)   # Fundulus catus wins
  )
  df$prior_mean           <- c(0.12, 0.05)
  df$score_likelihood     <- c(0.88, 0.60)
  df$score_likelihood_cov <- c(0.80, 0.55)

  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  # Fundulus catus has higher posterior despite lower prior/likelihood
  expect_equal(out$winner_prior,          0.05)
  expect_equal(out$winner_likelihood,     0.60)
  expect_equal(out$winner_likelihood_cov, 0.55)
})

test_that("winner columns are NA_real_ in empty consensus rows", {
  # All hypotheses below min_posterior -> empty row
  df <- make_posterior("s1", "Fundulus parvipinnis", "species",
                        "specific_candidate", 0.01)
  df$prior_mean           <- 0.10
  df$score_likelihood     <- 0.80
  df$score_likelihood_cov <- 0.75
  expect_warning(
    out <- posterior_consensus(df, rank_system = c("genus", "species"),
                               min_posterior = 0.05),
    "no hypotheses above min_posterior"
  )
  expect_true(is.na(out$winner_prior))
  expect_true(is.na(out$winner_likelihood))
  expect_true(is.na(out$winner_likelihood_cov))
})



test_that("posterior_consensus() no longer accepts uprank_trust_pvalue", {
  df <- make_posterior("s1", "Fundulus parvipinnis", "species",
                        "specific_candidate", 0.9)
  expect_error(
    posterior_consensus(df, rank_system = c("genus", "species"),
                         uprank_trust_pvalue = 0.001),
    "unused argument"
  )
})

# ==============================================================================
# winner_hypothesis_type / winner_rank_expanded (Session 149)
# ==============================================================================

test_that("winner_hypothesis_type/winner_rank_expanded columns are present", {
  df <- make_posterior("s1", "Fundulus parvipinnis", "species",
                        "specific_candidate", 0.9)
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_true(all(c("winner_hypothesis_type", "winner_rank_expanded") %in% names(out)))
})

test_that("winner_rank_expanded is FALSE for a normal specific_candidate winner", {
  df <- make_posterior(
    observation_id  = c("s1", "s1"),
    taxon_name      = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean  = c(0.7, 0.3)
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_equal(out$winner_hypothesis_type, "specific_candidate")
  expect_false(out$winner_rank_expanded)
})

test_that("winner_rank_expanded is TRUE when the winner came from coarse-rank expansion", {
  # Mimics join_priors()'s .expand_coarse_rank_rows() output: a family-level
  # ID with no species-level match data expanded into two species candidates
  # (different genera, as real Felidae congeners would be) sharing one
  # inherited (flat) likelihood/score -- the winner among them is decided
  # entirely by prior mass, not by any new evidence. cumulative_threshold is
  # lowered so only the single top hypothesis is "plausible" -- this test is
  # about the winner-diagnostic columns, not the LCA/rank behavior across
  # different-genus congeners (which correctly cannot resolve to species
  # when both are included in the plausible set).
  df <- make_posterior(
    observation_id  = c("s1", "s1"),
    taxon_name      = c("Lynx rufus", "Puma concolor"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("rank_expanded", 2),
    posterior_mean  = c(0.65, 0.35)   # tie-broken by prior alone
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"),
                             cumulative_threshold = 0.5)
  expect_equal(out$consensus_taxon, "Lynx rufus")
  expect_equal(out$winner_hypothesis_type, "rank_expanded")
  expect_true(out$winner_rank_expanded)
})

test_that("winner_hypothesis_type/winner_rank_expanded are NA in empty consensus rows", {
  df <- make_posterior("s1", "Fundulus parvipinnis", "species",
                        "specific_candidate", 0.01)
  expect_warning(
    out <- posterior_consensus(df, rank_system = c("genus", "species"),
                               min_posterior = 0.05),
    "no hypotheses above min_posterior"
  )
  expect_true(is.na(out$winner_hypothesis_type))
  expect_true(is.na(out$winner_rank_expanded))
})

test_that("missing required columns raises error", {
  df <- data.frame(observation_id = "s1", taxon_name = "Foo",
                    stringsAsFactors = FALSE)
  expect_error(posterior_consensus(df), "missing required column")
})

test_that("invalid cumulative_threshold raises error", {
  df <- make_posterior("s1", "Foo", "species", "specific_candidate", 0.9)
  expect_error(posterior_consensus(df, cumulative_threshold = 1.5),
               "cumulative_threshold")
  expect_error(posterior_consensus(df, cumulative_threshold = 0),
               "cumulative_threshold")
})

test_that("invalid min_posterior raises error", {
  df <- make_posterior("s1", "Foo", "species", "specific_candidate", 0.9)
  expect_error(posterior_consensus(df, min_posterior = -0.1),
               "min_posterior")
  expect_error(posterior_consensus(df, min_posterior = 1.0),
               "min_posterior")
})


# ==============================================================================
# Discrimination diagnostics (2026-07-27):
#   consensus_confusion_risk / primary_n_plausible_competitors /
#   consensus_n_plausible_competitors
# ==============================================================================

# Fixture: one observation, four species candidates across two genera in one
# family. `model_tier` marks which candidates have a real local occurrence
# record -- NA means "never reported here", which is what makes a candidate
# implausible for these counts.
make_competitor_df <- function(model_tier = c("tier1", "tier2", NA, NA),
                                posterior_mean = c(0.55, 0.20, 0.15, 0.10)) {
  df <- data.frame(
    observation_id  = rep("obs1", 4),
    taxon_name      = c("Aa one", "Aa two", "Bb one", "Bb two"),
    taxon_name_rank = rep("species", 4),
    hypothesis_type = rep("specific_candidate", 4),
    posterior_mean  = posterior_mean,
    posterior_point_est = posterior_mean,
    genus           = c("Aa", "Aa", "Bb", "Bb"),
    family          = rep("Fam1", 4),
    species         = c("Aa one", "Aa two", "Bb one", "Bb two"),
    model_tier      = model_tier,
    species_confusion_risk = rep(0.10, 4),
    genus_confusion_risk   = rep(0.30, 4),
    family_confusion_risk  = rep(0.60, 4),
    stringsAsFactors = FALSE
  )
  df
}

test_that("the three new diagnostic columns are always present", {
  out <- posterior_consensus(make_competitor_df(),
                             rank_system = c("family", "genus", "species"),
                             min_posterior = 0, cumulative_threshold = 1)
  expect_true(all(c("consensus_confusion_risk",
                    "primary_n_plausible_competitors",
                    "consensus_n_plausible_competitors") %in% names(out)))
})

test_that("primary_n_plausible_competitors counts plausible RIVALS, excluding the winner", {
  # Winner is "Aa one" (tier1). The only other plausible candidate is "Aa two".
  out <- posterior_consensus(make_competitor_df(),
                             rank_system = c("family", "genus", "species"),
                             min_posterior = 0, cumulative_threshold = 1)
  expect_equal(out$primary_n_plausible_competitors, 1L)
})

test_that("a win with no plausible rival at all reports 0, not 1", {
  # Only the winner itself is plausible -> nothing to lose to.
  out <- posterior_consensus(make_competitor_df(model_tier = c("tier1", NA, NA, NA)),
                             rank_system = c("family", "genus", "species"),
                             min_posterior = 0, cumulative_threshold = 1)
  expect_equal(out$primary_n_plausible_competitors, 0L)
})

test_that("an implausible winner still reports its plausible rivals (axes stay independent)", {
  # Winner "Aa one" is NOT plausible, but two rivals are. The count describes
  # the rivals, not the winner -- winner plausibility is winner_prior's job.
  out <- posterior_consensus(make_competitor_df(model_tier = c(NA, "tier1", "tier2", NA)),
                             rank_system = c("family", "genus", "species"),
                             min_posterior = 0, cumulative_threshold = 1)
  expect_equal(out$primary_n_plausible_competitors, 2L)
})

test_that("counts use every named hypothesis, not just the post-filter plausible set", {
  # min_posterior = 0.5 keeps only the winner in `plausible`, but the rival
  # still competed and must still be counted.
  out <- posterior_consensus(make_competitor_df(),
                             rank_system = c("family", "genus", "species"),
                             min_posterior = 0.5, cumulative_threshold = 0.9)
  expect_equal(out$n_plausible, 1L)
  expect_equal(out$primary_n_plausible_competitors, 1L)
})

test_that("consensus_n_plausible_competitors counts rival GROUPS at the consensus rank", {
  # Force a genus-level LCA by making the two genera tie, and make one
  # candidate in each genus plausible -> exactly 1 rival genus.
  df <- make_competitor_df(model_tier = c("tier1", NA, "tier1", NA),
                           posterior_mean = c(0.30, 0.20, 0.30, 0.20))
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"),
                             min_posterior = 0, cumulative_threshold = 1)
  expect_equal(out$consensus_rank, "family")   # LCA climbs past genus
  # At family rank both candidates are in Fam1, so there is no rival family.
  expect_equal(out$consensus_n_plausible_competitors, 0L)
})

test_that("consensus_confusion_risk is matched to consensus_rank, not the winner's own rank", {
  # Species-level consensus: one candidate dominates, so the cumulative
  # threshold admits only it and the LCA stays at species.
  out_sp <- posterior_consensus(
    make_competitor_df(posterior_mean = c(0.97, 0.01, 0.01, 0.01)),
    rank_system = c("family", "genus", "species"))
  expect_equal(out_sp$consensus_rank, "species")
  expect_equal(out_sp$consensus_confusion_risk, 0.10)

  # Family-level consensus -> family value, NOT the species one.
  df <- make_competitor_df(posterior_mean = c(0.30, 0.20, 0.30, 0.20))
  out_fam <- posterior_consensus(df, rank_system = c("family", "genus", "species"),
                                 min_posterior = 0, cumulative_threshold = 1)
  expect_equal(out_fam$consensus_rank, "family")
  expect_equal(out_fam$consensus_confusion_risk, 0.60)
  expect_equal(out_fam$winner_species_confusion_risk, 0.10)  # unchanged
})

test_that("counts are NA (not 0) when posterior_df carries no model_tier column", {
  df <- make_competitor_df(posterior_mean = c(0.97, 0.01, 0.01, 0.01))
  df$model_tier <- NULL
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_true(is.na(out$primary_n_plausible_competitors))
  expect_true(is.na(out$consensus_n_plausible_competitors))
  # confusion risk is independent of model_tier and must still be reported
  expect_equal(out$consensus_rank, "species")
  expect_equal(out$consensus_confusion_risk, 0.10)
})

# ==============================================================================
# Occurrence plausibility (2026-07-28/30): winner_theta_mean / consensus_prior
# now read theta_mean, never prior_mean (2026-07-30 fix, Task 0a)
# ==============================================================================
# prior_mean and theta_mean are set to DIVERGE deliberately -- Aa one carries
# a boosted prior_mean (0.99, as update_prior_from_consensus() would produce)
# but a modest true occurrence share (theta_mean = 0.02), so any test that
# reads winner_prior/consensus_prior interchangeably would fail loudly.

make_theta_df <- function(model_tier      = c("tier1", "tier2", NA, NA),
                           posterior_mean  = c(0.55, 0.20, 0.15, 0.10),
                           prior_mean      = c(0.99, 0.05, NA, NA),
                           theta_mean      = c(0.02, 0.05, NA, NA)) {
  df <- data.frame(
    observation_id  = rep("obs1", 4),
    taxon_name      = c("Aa one", "Aa two", "Bb one", "Bb two"),
    taxon_name_rank = rep("species", 4),
    hypothesis_type = rep("specific_candidate", 4),
    posterior_mean  = posterior_mean,
    posterior_point_est = posterior_mean,
    prior_mean      = prior_mean,
    theta_mean      = theta_mean,
    genus           = c("Aa", "Aa", "Bb", "Bb"),
    family          = rep("Fam1", 4),
    species         = c("Aa one", "Aa two", "Bb one", "Bb two"),
    model_tier      = model_tier,
    stringsAsFactors = FALSE
  )
  df
}

test_that("winner_theta_mean reads theta_mean, not the (possibly boosted) prior_mean", {
  df <- make_theta_df(posterior_mean = c(0.97, 0.01, 0.01, 0.01))
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_taxon, "Aa one")   # Aa one wins on posterior_mean
  expect_equal(out$winner_prior, 0.99)          # the boosted value, unchanged
  expect_equal(out$winner_theta_mean, 0.02)     # the TRUE occurrence share
})

test_that("winner_theta_mean is NA when theta_mean is absent from posterior_df", {
  df <- make_theta_df()
  df$theta_mean <- NULL
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_true(is.na(out$winner_theta_mean))
})

test_that("winner_has_occurrence_record is FALSE when no candidate has an occurrence record", {
  df <- make_theta_df(model_tier = c(NA, NA, NA, NA))
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_false(out$winner_has_occurrence_record)
})

test_that("winner_has_occurrence_record is unaffected by a boosted prior_mean", {
  df <- make_theta_df(posterior_mean = c(0.47, 0.47, 0.03, 0.03),
                      prior_mean     = c(0.9999, 0.05, NA, NA))
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_rank, "genus")
  expect_true(out$winner_has_occurrence_record)
})

# ==============================================================================
# consensus_prior via group_priors (2026-07-30, Task 1): SUM over ALL locally
# modelled group members, not just this observation's own candidates.
# consensus_prior REQUIRES group_priors -- there is no MAX fallback (removed
# 2026-07-30, per the user's explicit direction: the candidate-scoped MAX was
# a real underestimate, not a safe degrade-to value).
# ==============================================================================

test_that("consensus_prior is NA without group_priors, at any rank", {
  sp  <- posterior_consensus(make_theta_df(posterior_mean = c(0.97, 0.01, 0.01, 0.01)),
                             rank_system = c("family", "genus", "species"))
  gen <- posterior_consensus(make_theta_df(posterior_mean = c(0.47, 0.47, 0.03, 0.03)),
                             rank_system = c("family", "genus", "species"))
  expect_equal(sp$consensus_rank, "species")
  expect_true(is.na(sp$consensus_prior))
  expect_equal(gen$consensus_rank, "genus")
  expect_true(is.na(gen$consensus_prior))
})

test_that("group_priors drives consensus_prior when a matching (rank, taxon) row exists", {
  # Aa one/Aa two tie for the genus-level plausible set, but genus Aa has a
  # THIRD locally modelled member ("Aa three", theta_mean = 0.03) that never
  # appears as a candidate here -- group_priors knows about it, the
  # observation's own candidates don't.
  df <- make_theta_df(posterior_mean = c(0.47, 0.47, 0.03, 0.03))
  gp <- data.frame(rank = "genus", taxon = "Aa", theta_sum = 0.02 + 0.05 + 0.03,
                   n_members = 3L, stringsAsFactors = FALSE)
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"),
                             group_priors = gp)
  expect_equal(out$consensus_rank, "genus")
  expect_equal(out$consensus_prior, 0.10)
})

test_that("consensus_prior at genus rank is unaffected by a boosted prior_mean", {
  df <- make_theta_df(posterior_mean = c(0.47, 0.47, 0.03, 0.03),
                      prior_mean     = c(0.9999, 0.05, NA, NA))
  gp <- data.frame(rank = "genus", taxon = "Aa", theta_sum = 0.02 + 0.05,
                   n_members = 2L, stringsAsFactors = FALSE)
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"),
                             group_priors = gp)
  expect_equal(out$consensus_prior, 0.07)   # unaffected by winner_prior = 0.9999
})

test_that("consensus_prior is NA when group_priors has no matching row", {
  df <- make_theta_df(posterior_mean = c(0.47, 0.47, 0.03, 0.03))
  gp <- data.frame(rank = "genus", taxon = "SomeOtherGenus", theta_sum = 0.5,
                   n_members = 4L, stringsAsFactors = FALSE)
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"),
                             group_priors = gp)
  expect_true(is.na(out$consensus_prior))
})

test_that("group_priors can supply a species-rank entry too", {
  df <- make_theta_df(posterior_mean = c(0.97, 0.01, 0.01, 0.01))
  gp <- data.frame(rank = "species", taxon = "Aa one", theta_sum = 0.02,
                   n_members = 1L, stringsAsFactors = FALSE)
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"),
                             group_priors = gp)
  expect_equal(out$consensus_rank, "species")
  expect_equal(out$consensus_prior, 0.02)
})

test_that("stops on invalid group_priors", {
  df <- make_theta_df()
  expect_error(
    posterior_consensus(df, rank_system = c("family", "genus", "species"), group_priors = "x"),
    "group_priors"
  )
  gp_bad <- data.frame(rank = "genus", taxon = "Aa")   # missing theta_sum
  expect_error(
    posterior_consensus(df, rank_system = c("family", "genus", "species"), group_priors = gp_bad),
    "theta_sum"
  )
})

# ==============================================================================
# consensus_has_occurrence_record (2026-07-30): the real presence signal
# consensus_prior's NA can no longer safely double as -- fixes a real bug
# where consensus_plausibility misread "group_priors never supplied" as
# "confirmed absent" on real production data (0 workflows wire in
# group_priors yet, so consensus_prior was NA -- and thus misread as
# unprecedented -- for every single row).
# ==============================================================================

test_that("consensus_has_occurrence_record is NA when group_priors is NULL (not checked)", {
  df <- make_theta_df(posterior_mean = c(0.47, 0.47, 0.03, 0.03))
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_true(is.na(out$consensus_has_occurrence_record))
})

test_that("consensus_has_occurrence_record is TRUE when group_priors has a matching row", {
  df <- make_theta_df(posterior_mean = c(0.47, 0.47, 0.03, 0.03))
  gp <- data.frame(rank = "genus", taxon = "Aa", theta_sum = 0.07,
                   n_members = 2L, stringsAsFactors = FALSE)
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"),
                             group_priors = gp)
  expect_true(out$consensus_has_occurrence_record)
})

test_that("consensus_has_occurrence_record is FALSE (confirmed absent) when group_priors has no match", {
  df <- make_theta_df(posterior_mean = c(0.47, 0.47, 0.03, 0.03))
  gp <- data.frame(rank = "genus", taxon = "SomeOtherGenus", theta_sum = 0.5,
                   n_members = 4L, stringsAsFactors = FALSE)
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"),
                             group_priors = gp)
  expect_false(out$consensus_has_occurrence_record)
  expect_true(is.na(out$consensus_prior))
})
