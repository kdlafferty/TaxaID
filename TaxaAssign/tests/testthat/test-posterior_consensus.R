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
