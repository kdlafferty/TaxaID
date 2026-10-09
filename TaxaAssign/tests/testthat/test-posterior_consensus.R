# test-posterior_consensus.R

# ==============================================================================
# Helpers
# ==============================================================================

make_posterior <- function(observation_id, taxon_name, taxon_name_rank,
                           hypothesis_type, posterior_mean,
                           genus = NULL, family = NULL, species = NULL) {
  df <- data.frame(
    observation_id = observation_id,
    taxon_name = taxon_name,
    taxon_name_rank = taxon_name_rank,
    hypothesis_type = hypothesis_type,
    posterior_mean = posterior_mean,
    # mirrored so fixtures exercise the (2026-08-28) default
    # posterior_col = "posterior_point_est" without each test opting in
    posterior_point_est = posterior_mean,
    stringsAsFactors = FALSE
  )
  if (!is.null(genus)) df$genus <- genus
  if (!is.null(family)) df$family <- family
  if (!is.null(species)) df$species <- species
  df
}


# ==============================================================================
# Basic structure
# ==============================================================================

test_that("returns one row per observation_id", {
  df <- make_posterior(
    observation_id = c("s1", "s1", "s2"),
    taxon_name = c("Fundulus parvipinnis", "Fundulus catus", "Gobiosoma bosc"),
    taxon_name_rank = c("species", "species", "species"),
    hypothesis_type = rep("specific_candidate", 3),
    posterior_mean = c(0.6, 0.4, 1.0)
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_equal(nrow(out), 2L)
  expect_equal(sort(out$observation_id), c("s1", "s2"))
})

test_that("output has required columns", {
  df <- make_posterior(
    "s1", "Fundulus parvipinnis", "species",
    "specific_candidate", 1.0
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_true(all(c(
    "observation_id", "consensus_taxon", "consensus_rank",
    "is_resolved", "n_plausible",
    "plausible_taxa", "plausible_posteriors"
  ) %in% names(out)))
})


# ==============================================================================
# Single-hypothesis samples
# ==============================================================================

test_that("single unambiguous species resolves to species", {
  df <- make_posterior(
    "s1", "Fundulus parvipinnis", "species",
    "specific_candidate", 0.95
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_equal(out$consensus_taxon, "Fundulus parvipinnis")
  expect_equal(out$consensus_rank, "species")
  expect_true(out$is_resolved)
  expect_equal(out$n_plausible, 1L)
})

test_that("single genus-rank hypothesis resolves at genus", {
  df <- make_posterior(
    "s1", "Fundulus", "genus",
    "specific_candidate", 0.9
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_equal(out$consensus_taxon, "Fundulus")
  expect_equal(out$consensus_rank, "genus")
  expect_false(out$is_resolved) # genus is not the finest rank (species is)
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

test_that("two species in same genus -> LCA at genus (derived from binomial)", {
  df <- make_posterior(
    observation_id = c("s1", "s1"),
    taxon_name = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = c("species", "species"),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean = c(0.55, 0.45)
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_equal(out$consensus_taxon, "Fundulus")
  expect_equal(out$consensus_rank, "genus")
  expect_false(out$is_resolved)
})

test_that("two species in different genera -> LCA at family (explicit column)", {
  df <- make_posterior(
    observation_id = c("s1", "s1"),
    taxon_name = c("Fundulus parvipinnis", "Gobiosoma bosc"),
    taxon_name_rank = c("species", "species"),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean = c(0.55, 0.45),
    family = c("Fundulidae", "Gobiidae")
  )
  # Same family -> LCA = family
  df$family <- c("Gobiidae", "Gobiidae") # force same family
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_rank, "family")
  expect_false(out$is_resolved)
})

test_that("species in different families with no shared rank -> NA", {
  df <- make_posterior(
    observation_id = c("s1", "s1"),
    taxon_name = c("Fundulus parvipinnis", "Gobiosoma bosc"),
    taxon_name_rank = c("species", "species"),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean = c(0.55, 0.45),
    family = c("Fundulidae", "Gobiidae")
  )
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_true(is.na(out$consensus_taxon))
  expect_true(is.na(out$consensus_rank))
})


# ==============================================================================
# Cumulative threshold
# ==============================================================================

test_that("cumulative_threshold limits included hypotheses", {
  # First species alone accounts for 0.91 of named mass -> only 1 included
  df <- make_posterior(
    observation_id = c("s1", "s1", "s1"),
    taxon_name = c("Fundulus parvipinnis", "Fundulus catus", "Fundulus nottii"),
    taxon_name_rank = rep("species", 3),
    hypothesis_type = rep("specific_candidate", 3),
    posterior_mean = c(0.91, 0.05, 0.04)
  )
  out <- posterior_consensus(df,
    rank_system = c("genus", "species"),
    cumulative_threshold = 0.9
  )
  expect_equal(out$n_plausible, 1L)
  expect_equal(out$consensus_taxon, "Fundulus parvipinnis")
  expect_true(out$is_resolved)
})

test_that("lower cumulative_threshold can resolve to species from two-way tie", {
  df <- make_posterior(
    observation_id = c("s1", "s1"),
    taxon_name = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean = c(0.8, 0.2)
  )
  # With threshold 0.75, only the top species (0.8/1.0 = 80% >= 75%) is included
  out <- posterior_consensus(df,
    rank_system = c("genus", "species"),
    cumulative_threshold = 0.75
  )
  expect_equal(out$n_plausible, 1L)
  expect_equal(out$consensus_taxon, "Fundulus parvipinnis")
})


# ==============================================================================
# min_posterior filter
# ==============================================================================

test_that("hypotheses below min_posterior are excluded before LCA", {
  # Second species is 0.03 < 0.05 -> excluded -> single species resolves
  df <- make_posterior(
    observation_id = c("s1", "s1"),
    taxon_name = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean = c(0.97, 0.03)
  )
  out <- posterior_consensus(df,
    rank_system = c("genus", "species"),
    min_posterior = 0.05
  )
  expect_equal(out$n_plausible, 1L)
  expect_equal(out$consensus_taxon, "Fundulus parvipinnis")
})

test_that("all hypotheses below min_posterior -> empty row", {
  df <- make_posterior(
    observation_id = c("s1", "s1"),
    taxon_name = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean = c(0.04, 0.03)
  )
  out <- posterior_consensus(df,
    rank_system = c("genus", "species"),
    min_posterior = 0.05
  )
  expect_equal(out$n_plausible, 0L)
  expect_true(is.na(out$consensus_taxon))
  expect_false(out$is_resolved)
})


# ==============================================================================
# Hypothesis type filtering
# ==============================================================================

test_that("unreferenced_family rows are excluded from LCA", {
  df <- rbind(
    make_posterior(
      "s1", "Fundulus parvipinnis", "species",
      "specific_candidate", 0.6
    ),
    make_posterior(
      "s1", NA_character_, NA_character_,
      "unreferenced_family", 0.4
    )
  )
  # The catch-all cannot join the LCA, but its 0.4 is mass the call does not
  # hold: with unnamed_in_threshold = TRUE (default) 0.6 < 0.9 of the total,
  # so the observation is unresolved.
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_true(is.na(out$consensus_taxon))
  expect_equal(out$consensus_reason, "unnamed_mass")
  expect_equal(out$unnamed_mass, 0.4)
  # named-only threshold: only Fundulus parvipinnis contributes -> resolved
  old <- posterior_consensus(df, rank_system = c("genus", "species"), unnamed_in_threshold = FALSE)
  expect_equal(old$n_plausible, 1L)
  expect_equal(old$consensus_taxon, "Fundulus parvipinnis")
  expect_true(old$is_resolved)
})

test_that("unreferenced_genus named species are included in LCA", {
  # Family-level unreferenced taxon: species from a genus absent in the reference.
  # Should widen LCA just like unreferenced_species.
  df <- rbind(
    make_posterior(
      "s1", "Fundulus parvipinnis", "species",
      "specific_candidate", 0.7
    ),
    make_posterior(
      "s1", "Hesperoleucus symmetricus", "species",
      "unreferenced_genus", 0.3
    )
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  # Different genera -> LCA cannot resolve at genus -> NA (no shared family column)
  expect_equal(out$n_plausible, 2L)
})

test_that("unreferenced_genus family-level unreferenced taxa resolve at family when column present", {
  df <- rbind(
    make_posterior("s1", "Fundulus parvipinnis", "species",
      "specific_candidate", 0.7,
      family = "Leuciscidae"
    ),
    make_posterior("s1", "Hesperoleucus symmetricus", "species",
      "unreferenced_genus", 0.3,
      family = "Leuciscidae"
    )
  )
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_rank, "family")
  expect_equal(out$consensus_taxon, "Leuciscidae")
  expect_equal(out$n_plausible, 2L)
})

test_that("unreferenced_species rows are included in LCA", {
  df <- rbind(
    make_posterior(
      "s1", "Fundulus parvipinnis", "species",
      "specific_candidate", 0.55
    ),
    make_posterior(
      "s1", "Fundulus sp_unref", "species",
      "unreferenced_species", 0.45
    )
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  # Both are Fundulus -> LCA at genus
  expect_equal(out$consensus_rank, "genus")
  expect_equal(out$consensus_taxon, "Fundulus")
  expect_equal(out$n_plausible, 2L)
})


# ==============================================================================
# No named hypotheses -> empty row
# ==============================================================================

test_that("sample with only unreferenced_family -> empty row", {
  df <- make_posterior(
    "s1", NA_character_, NA_character_,
    "unreferenced_family", 1.0
  )
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
    observation_id = c("s1", "s1"),
    taxon_name = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean = c(0.7, 0.3)
  )
  out <- posterior_consensus(df,
    rank_system = c("genus", "species"),
    cumulative_threshold = 1.0
  )
  taxa <- out$plausible_taxa[[1]]
  posts <- out$plausible_posteriors[[1]]
  expect_equal(taxa[1], "Fundulus parvipinnis") # sorted descending
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
    observation_id = c("s1", "s1"),
    taxon_name = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean = c(0.55, 0.45),
    genus = c("Fundulus", "Fundulus")
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
  df <- make_posterior(
    "s1", "Fundulus parvipinnis", "species",
    "specific_candidate", 0.9
  )
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_true(all(c(
    "winner_prior", "winner_likelihood",
    "winner_likelihood_cov"
  ) %in% names(out)))
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
  df$prior_mean <- c(0.12, 0.05)
  df$score_likelihood <- c(0.88, 0.60)
  df$score_likelihood_cov <- c(0.80, 0.55)

  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  # Winner is Fundulus parvipinnis (posterior_mean = 0.7)
  expect_equal(out$winner_prior, 0.12)
  expect_equal(out$winner_likelihood, 0.88)
  expect_equal(out$winner_likelihood_cov, 0.80)
})

test_that("winner columns reflect actual winner, not highest likelihood", {
  # Ensure the winner is determined by posterior, not by likelihood
  df <- make_posterior(
    observation_id  = c("s1", "s1"),
    taxon_name      = c("Fundulus parvipinnis", "Fundulus catus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean  = c(0.3, 0.7) # Fundulus catus wins
  )
  df$prior_mean <- c(0.12, 0.05)
  df$score_likelihood <- c(0.88, 0.60)
  df$score_likelihood_cov <- c(0.80, 0.55)

  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  # Fundulus catus has higher posterior despite lower prior/likelihood
  expect_equal(out$winner_prior, 0.05)
  expect_equal(out$winner_likelihood, 0.60)
  expect_equal(out$winner_likelihood_cov, 0.55)
})

test_that("winner columns are NA_real_ in empty consensus rows", {
  # All hypotheses below min_posterior -> empty row
  df <- make_posterior(
    "s1", "Fundulus parvipinnis", "species",
    "specific_candidate", 0.01
  )
  df$prior_mean <- 0.10
  df$score_likelihood <- 0.80
  df$score_likelihood_cov <- 0.75
  expect_warning(
    out <- posterior_consensus(df,
      rank_system = c("genus", "species"),
      min_posterior = 0.05
    ),
    "no hypotheses above min_posterior"
  )
  expect_true(is.na(out$winner_prior))
  expect_true(is.na(out$winner_likelihood))
  expect_true(is.na(out$winner_likelihood_cov))
})


test_that("posterior_consensus() no longer accepts uprank_trust_pvalue", {
  df <- make_posterior(
    "s1", "Fundulus parvipinnis", "species",
    "specific_candidate", 0.9
  )
  expect_error(
    posterior_consensus(df,
      rank_system = c("genus", "species"),
      uprank_trust_pvalue = 0.001
    ),
    "unused argument"
  )
})

# ==============================================================================
# winner_hypothesis_type / winner_rank_expanded (Session 149)
# ==============================================================================

test_that("winner_hypothesis_type/winner_rank_expanded columns are present", {
  df <- make_posterior(
    "s1", "Fundulus parvipinnis", "species",
    "specific_candidate", 0.9
  )
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
    posterior_mean  = c(0.65, 0.35) # tie-broken by prior alone
  )
  out <- posterior_consensus(df,
    rank_system = c("genus", "species"),
    cumulative_threshold = 0.5
  )
  expect_equal(out$consensus_taxon, "Lynx rufus")
  expect_equal(out$winner_hypothesis_type, "rank_expanded")
  expect_true(out$winner_rank_expanded)
})

test_that("winner_hypothesis_type/winner_rank_expanded are NA in empty consensus rows", {
  df <- make_posterior(
    "s1", "Fundulus parvipinnis", "species",
    "specific_candidate", 0.01
  )
  expect_warning(
    out <- posterior_consensus(df,
      rank_system = c("genus", "species"),
      min_posterior = 0.05
    ),
    "no hypotheses above min_posterior"
  )
  expect_true(is.na(out$winner_hypothesis_type))
  expect_true(is.na(out$winner_rank_expanded))
})

test_that("missing required columns raises error", {
  df <- data.frame(
    observation_id = "s1", taxon_name = "Foo",
    stringsAsFactors = FALSE
  )
  expect_error(posterior_consensus(df), "missing required column")
})

test_that("invalid cumulative_threshold raises error", {
  df <- make_posterior("s1", "Foo", "species", "specific_candidate", 0.9)
  expect_error(
    posterior_consensus(df, cumulative_threshold = 1.5),
    "cumulative_threshold"
  )
  expect_error(
    posterior_consensus(df, cumulative_threshold = 0),
    "cumulative_threshold"
  )
})

test_that("invalid min_posterior raises error", {
  df <- make_posterior("s1", "Foo", "species", "specific_candidate", 0.9)
  expect_error(
    posterior_consensus(df, min_posterior = -0.1),
    "min_posterior"
  )
  expect_error(
    posterior_consensus(df, min_posterior = 1.0),
    "min_posterior"
  )
})


# ==============================================================================
# Discrimination diagnostics (2026-07-27):
#   consensus_confusion_risk / primary_n_plausible_competitors /
#   consensus_n_plausible_competitors
# ==============================================================================

# Fixture: one observation, four species candidates across two genera in one
# family. `prior_branch` marks which candidates have a real local occurrence
# record -- NA means "never reported here", which is what makes a candidate
# implausible for these counts.
make_competitor_df <- function(prior_branch = c("kernel_estimated", "resident_undetected", NA, NA),
                               posterior_mean = c(0.55, 0.20, 0.15, 0.10)) {
  df <- data.frame(
    observation_id = rep("obs1", 4),
    taxon_name = c("Aa one", "Aa two", "Bb one", "Bb two"),
    taxon_name_rank = rep("species", 4),
    hypothesis_type = rep("specific_candidate", 4),
    posterior_mean = posterior_mean,
    posterior_point_est = posterior_mean,
    genus = c("Aa", "Aa", "Bb", "Bb"),
    family = rep("Fam1", 4),
    species = c("Aa one", "Aa two", "Bb one", "Bb two"),
    prior_branch = prior_branch,
    species_confusion_risk = rep(0.10, 4),
    genus_confusion_risk = rep(0.30, 4),
    family_confusion_risk = rep(0.60, 4),
    stringsAsFactors = FALSE
  )
  df
}

test_that("the three new diagnostic columns are always present", {
  out <- posterior_consensus(make_competitor_df(),
    rank_system = c("family", "genus", "species"),
    min_posterior = 0, cumulative_threshold = 1
  )
  expect_true(all(c(
    "consensus_confusion_risk",
    "primary_n_plausible_competitors",
    "consensus_n_plausible_competitors"
  ) %in% names(out)))
})

test_that("primary_n_plausible_competitors counts plausible RIVALS, excluding the winner", {
  # Winner is "Aa one" (tier1). The only other plausible candidate is "Aa two".
  out <- posterior_consensus(make_competitor_df(),
    rank_system = c("family", "genus", "species"),
    min_posterior = 0, cumulative_threshold = 1
  )
  expect_equal(out$primary_n_plausible_competitors, 1L)
})

test_that("a win with no plausible rival at all reports 0, not 1", {
  # Only the winner itself is plausible -> nothing to lose to.
  out <- posterior_consensus(make_competitor_df(prior_branch = c("kernel_estimated", NA, NA, NA)),
    rank_system = c("family", "genus", "species"),
    min_posterior = 0, cumulative_threshold = 1
  )
  expect_equal(out$primary_n_plausible_competitors, 0L)
})

test_that("an implausible winner still reports its plausible rivals (axes stay independent)", {
  # Winner "Aa one" is NOT plausible, but two rivals are. The count describes
  # the rivals, not the winner -- winner plausibility is winner_prior's job.
  out <- posterior_consensus(make_competitor_df(prior_branch = c(NA, "kernel_estimated", "resident_undetected", NA)),
    rank_system = c("family", "genus", "species"),
    min_posterior = 0, cumulative_threshold = 1
  )
  expect_equal(out$primary_n_plausible_competitors, 2L)
})

test_that("counts use every named hypothesis, not just the post-filter plausible set", {
  # min_posterior = 0.5 keeps only the winner in `plausible`, but the rival
  # still competed and must still be counted.
  out <- posterior_consensus(make_competitor_df(),
    rank_system = c("family", "genus", "species"),
    min_posterior = 0.5, cumulative_threshold = 0.9
  )
  expect_equal(out$n_plausible, 1L)
  expect_equal(out$primary_n_plausible_competitors, 1L)
})

test_that("consensus_n_plausible_competitors counts rival GROUPS at the consensus rank", {
  # Force a genus-level LCA by making the two genera tie, and make one
  # candidate in each genus plausible -> exactly 1 rival genus.
  df <- make_competitor_df(
    prior_branch = c("kernel_estimated", NA, "kernel_estimated", NA),
    posterior_mean = c(0.30, 0.20, 0.30, 0.20)
  )
  out <- posterior_consensus(df,
    rank_system = c("family", "genus", "species"),
    min_posterior = 0, cumulative_threshold = 1
  )
  expect_equal(out$consensus_rank, "family") # LCA climbs past genus
  # At family rank both candidates are in Fam1, so there is no rival family.
  expect_equal(out$consensus_n_plausible_competitors, 0L)
})

test_that("consensus_confusion_risk is matched to consensus_rank, not the winner's own rank", {
  # Species-level consensus: one candidate dominates, so the cumulative
  # threshold admits only it and the LCA stays at species.
  out_sp <- posterior_consensus(
    make_competitor_df(posterior_mean = c(0.97, 0.01, 0.01, 0.01)),
    rank_system = c("family", "genus", "species")
  )
  expect_equal(out_sp$consensus_rank, "species")
  expect_equal(out_sp$consensus_confusion_risk, 0.10)

  # Family-level consensus -> family value, NOT the species one.
  df <- make_competitor_df(posterior_mean = c(0.30, 0.20, 0.30, 0.20))
  out_fam <- posterior_consensus(df,
    rank_system = c("family", "genus", "species"),
    min_posterior = 0, cumulative_threshold = 1
  )
  expect_equal(out_fam$consensus_rank, "family")
  expect_equal(out_fam$consensus_confusion_risk, 0.60)
  expect_equal(out_fam$winner_species_confusion_risk, 0.10) # unchanged
})

test_that("counts are NA (not 0) when posterior_df carries no prior_branch column", {
  df <- make_competitor_df(posterior_mean = c(0.97, 0.01, 0.01, 0.01))
  df$prior_branch <- NULL
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_true(is.na(out$primary_n_plausible_competitors))
  expect_true(is.na(out$consensus_n_plausible_competitors))
  # confusion risk is independent of prior_branch and must still be reported
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

make_theta_df <- function(model_tier = c("tier1", "tier2", NA, NA),
                          prior_branch = ifelse(is.na(model_tier), NA_character_, "kernel_estimated"),
                          posterior_mean = c(0.55, 0.20, 0.15, 0.10),
                          prior_mean = c(0.99, 0.05, NA, NA),
                          theta_mean = c(0.02, 0.05, NA, NA)) {
  df <- data.frame(
    observation_id = rep("obs1", 4),
    taxon_name = c("Aa one", "Aa two", "Bb one", "Bb two"),
    taxon_name_rank = rep("species", 4),
    hypothesis_type = rep("specific_candidate", 4),
    posterior_mean = posterior_mean,
    posterior_point_est = posterior_mean,
    prior_mean = prior_mean,
    theta_mean = theta_mean,
    genus = c("Aa", "Aa", "Bb", "Bb"),
    family = rep("Fam1", 4),
    species = c("Aa one", "Aa two", "Bb one", "Bb two"),
    model_tier = model_tier,
    prior_branch = prior_branch,
    stringsAsFactors = FALSE
  )
  df
}

test_that("winner_theta_mean reads theta_mean, not the (possibly boosted) prior_mean", {
  df <- make_theta_df(posterior_mean = c(0.97, 0.01, 0.01, 0.01))
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_taxon, "Aa one") # Aa one wins on posterior_mean
  expect_equal(out$winner_prior, 0.99) # the boosted value, unchanged
  expect_equal(out$winner_theta_mean, 0.02) # the TRUE occurrence share
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
  df <- make_theta_df(
    posterior_mean = c(0.47, 0.47, 0.03, 0.03),
    prior_mean = c(0.9999, 0.05, NA, NA)
  )
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_rank, "genus")
  expect_true(out$winner_has_occurrence_record)
})

# ==============================================================================
# Kernel-priors schema: winner_has_occurrence_record and the
# plausible-competitor counts read prior_branch; model_tier is never
# consulted for either. Real-bug regression this prevents: kernel tables
# carry model_tier only as a legacy column on their undetected/domestic rows
# (NA on every locally-evidenced resident row), so reading model_tier in
# prior_branch's place is exactly INVERTED (confirmed on real GreatLakes
# kernel output: 873/885 winners read "unprecedented"; the only TRUE rows
# were evidence-blend species with ZERO local records).
# ==============================================================================

test_that("winner_has_occurrence_record reads prior_branch, ignoring model_tier", {
  # model_tier is set to the OPPOSITE of what prior_branch implies, so a test
  # that accidentally read model_tier instead would fail loudly.
  df <- make_theta_df(
    model_tier = c(NA, "tier_undetected_evidence", NA, NA),
    posterior_mean = c(0.97, 0.01, 0.01, 0.01)
  )
  df$prior_branch <- c("kernel_estimated", "resident_undetected", NA, NA)
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_taxon, "Aa one")
  expect_true(out$winner_has_occurrence_record)

  # An evidence-elevated winner (zero local records) reads FALSE, even though
  # its model_tier is non-NA.
  df2 <- make_theta_df(
    model_tier = c("tier_undetected_evidence", NA, NA, NA),
    posterior_mean = c(0.97, 0.01, 0.01, 0.01)
  )
  df2$prior_branch <- c("resident_undetected", "kernel_estimated", NA, NA)
  out2 <- posterior_consensus(df2, rank_system = c("family", "genus", "species"))
  expect_equal(out2$consensus_taxon, "Aa one")
  expect_false(out2$winner_has_occurrence_record)
})

test_that("transport (domestic/food) winners read FALSE under the kernel schema", {
  df <- make_theta_df(
    model_tier = c("tier_domestic_food", NA, NA, NA),
    posterior_mean = c(0.97, 0.01, 0.01, 0.01)
  )
  df$prior_branch <- c("transport", NA, NA, NA)
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_false(out$winner_has_occurrence_record)
})

test_that("plausible-competitor counts read prior_branch when present", {
  # Winner Aa one (resident) + one named rival on any branch = 1 competitor;
  # the two floor rows (NA branch) never count.
  df <- make_theta_df(model_tier = c(NA, NA, NA, NA))
  df$prior_branch <- c("kernel_estimated", "transport", NA, NA)
  out <- posterior_consensus(df, rank_system = c("family", "genus", "species"))
  expect_equal(out$primary_n_plausible_competitors, 1L)
})

test_that("a model_tier column with no prior_branch column is an error", {
  # 1.0 has no predecessor: a prior table that predates the kernel-priors
  # schema (model_tier without prior_branch) must fail loudly, not fall back
  # to the model_tier reading -- see posterior_consensus.R's own docs on why
  # that reading is exactly inverted on real kernel tables.
  df <- make_theta_df(model_tier = c("tier1", NA, NA, NA))
  df$prior_branch <- NULL
  expect_error(
    posterior_consensus(df, rank_system = c("family", "genus", "species")),
    "model_tier.*prior_branch"
  )
})

# ==============================================================================
# consensus_prior via group_priors (2026-07-30, Task 1): SUM over ALL locally
# modelled group members, not just this observation's own candidates.
# consensus_prior REQUIRES group_priors -- there is no MAX fallback (removed
# 2026-07-30, per the user's explicit direction: the candidate-scoped MAX was
# a real underestimate, not a safe degrade-to value).
# ==============================================================================

test_that("consensus_prior is NA without group_priors, at any rank", {
  sp <- posterior_consensus(make_theta_df(posterior_mean = c(0.97, 0.01, 0.01, 0.01)),
    rank_system = c("family", "genus", "species")
  )
  gen <- posterior_consensus(make_theta_df(posterior_mean = c(0.47, 0.47, 0.03, 0.03)),
    rank_system = c("family", "genus", "species")
  )
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
  gp <- data.frame(
    rank = "genus", taxon = "Aa", theta_sum = 0.02 + 0.05 + 0.03,
    n_members = 3L, stringsAsFactors = FALSE
  )
  out <- posterior_consensus(df,
    rank_system = c("family", "genus", "species"),
    group_priors = gp
  )
  expect_equal(out$consensus_rank, "genus")
  expect_equal(out$consensus_prior, 0.10)
})

test_that("consensus_prior at genus rank is unaffected by a boosted prior_mean", {
  df <- make_theta_df(
    posterior_mean = c(0.47, 0.47, 0.03, 0.03),
    prior_mean = c(0.9999, 0.05, NA, NA)
  )
  gp <- data.frame(
    rank = "genus", taxon = "Aa", theta_sum = 0.02 + 0.05,
    n_members = 2L, stringsAsFactors = FALSE
  )
  out <- posterior_consensus(df,
    rank_system = c("family", "genus", "species"),
    group_priors = gp
  )
  expect_equal(out$consensus_prior, 0.07) # unaffected by winner_prior = 0.9999
})

test_that("consensus_prior is NA when group_priors has no matching row", {
  df <- make_theta_df(posterior_mean = c(0.47, 0.47, 0.03, 0.03))
  gp <- data.frame(
    rank = "genus", taxon = "SomeOtherGenus", theta_sum = 0.5,
    n_members = 4L, stringsAsFactors = FALSE
  )
  out <- posterior_consensus(df,
    rank_system = c("family", "genus", "species"),
    group_priors = gp
  )
  expect_true(is.na(out$consensus_prior))
})

test_that("group_priors can supply a species-rank entry too", {
  df <- make_theta_df(posterior_mean = c(0.97, 0.01, 0.01, 0.01))
  gp <- data.frame(
    rank = "species", taxon = "Aa one", theta_sum = 0.02,
    n_members = 1L, stringsAsFactors = FALSE
  )
  out <- posterior_consensus(df,
    rank_system = c("family", "genus", "species"),
    group_priors = gp
  )
  expect_equal(out$consensus_rank, "species")
  expect_equal(out$consensus_prior, 0.02)
})

test_that("stops on invalid group_priors", {
  df <- make_theta_df()
  expect_error(
    posterior_consensus(df, rank_system = c("family", "genus", "species"), group_priors = "x"),
    "group_priors"
  )
  gp_bad <- data.frame(rank = "genus", taxon = "Aa") # missing theta_sum
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
  gp <- data.frame(
    rank = "genus", taxon = "Aa", theta_sum = 0.07,
    n_members = 2L, stringsAsFactors = FALSE
  )
  out <- posterior_consensus(df,
    rank_system = c("family", "genus", "species"),
    group_priors = gp
  )
  expect_true(out$consensus_has_occurrence_record)
})

test_that("consensus_has_occurrence_record is FALSE (confirmed absent) when group_priors has no match", {
  df <- make_theta_df(posterior_mean = c(0.47, 0.47, 0.03, 0.03))
  gp <- data.frame(
    rank = "genus", taxon = "SomeOtherGenus", theta_sum = 0.5,
    n_members = 4L, stringsAsFactors = FALSE
  )
  out <- posterior_consensus(df,
    rank_system = c("family", "genus", "species"),
    group_priors = gp
  )
  expect_false(out$consensus_has_occurrence_record)
  expect_true(is.na(out$consensus_prior))
})

test_that("errors clearly (not a cryptic subscript-out-of-bounds) when no rank columns can be detected and rank_system is NULL", {
  # Reproduces TaxaLikely::evaluate_likelihoods()'s own output shape -- only
  # taxon_name/taxon_name_rank, no kingdom..species rank columns at all --
  # found 2026-09-05 building diagnostics/fast_workflows/run_fast_smoketest.R.
  df <- data.frame(
    observation_id      = "obs1",
    taxon_name          = c("Perca flavescens", "Perca fluviatilis"),
    taxon_name_rank     = "species",
    hypothesis_type     = "specific_candidate",
    posterior_point_est = c(0.6, 0.4),
    stringsAsFactors    = FALSE
  )
  expect_error(
    suppressWarnings(posterior_consensus(df)),
    "could not auto-detect any rank columns"
  )
  # Passing rank_system explicitly -- exactly the documented workaround --
  # still works fine even though no genus/species COLUMNS exist.
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_equal(nrow(out), 1L)
})

# ==============================================================================
# Downranking: candidate-set gate (2026-09-13, ecosystem review C2)
# ==============================================================================

test_that("downranking is blocked when the reference's only finer taxon was never a candidate", {
  # Mugu shape: a genus LCA over three congeners; the reference knows exactly
  # one Pseudotolithus locally, but it is not one of the three scored.
  df <- make_posterior(
    observation_id = rep("ASV_1", 3),
    taxon_name = c("Pseudotolithus epipercus", "Pseudotolithus typus", "Pseudotolithus elongatus"),
    taxon_name_rank = rep("species", 3),
    hypothesis_type = rep("specific_candidate", 3),
    posterior_mean = c(0.50, 0.27, 0.11),
    genus = rep("Pseudotolithus", 3)
  )
  ref <- data.frame(
    taxon_name = "Pseudotolithus senegallus",
    genus = "Pseudotolithus",
    stringsAsFactors = FALSE
  )
  rs <- c("genus", "species")
  gated <- suppressMessages(posterior_consensus(df, rank_system = rs, species_reference = ref))
  expect_equal(gated$consensus_taxon, "Pseudotolithus")
  expect_equal(gated$consensus_rank, "genus")
  expect_false(gated$downranked)

  # The pre-2026-09-13 behaviour is still available and still does the relabel.
  ungated <- suppressMessages(posterior_consensus(
    df, rank_system = rs, species_reference = ref, downrank_requires_candidate = FALSE
  ))
  expect_equal(ungated$consensus_taxon, "Pseudotolithus senegallus")
  expect_true(ungated$downranked)
})

test_that("a narrowing to a taxon that IS a scored candidate still happens", {
  df <- make_posterior(
    observation_id = rep("ASV_2", 2),
    taxon_name = c("Girella nigricans", "Girella simplicidens"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean = c(0.55, 0.45),
    genus = rep("Girella", 2)
  )
  ref <- data.frame(
    taxon_name = "Girella nigricans", genus = "Girella",
    stringsAsFactors = FALSE
  )
  out <- suppressMessages(posterior_consensus(
    df, rank_system = c("genus", "species"), species_reference = ref
  ))
  expect_equal(out$consensus_taxon, "Girella nigricans")
  expect_true(out$downranked)
})

test_that("a coarser downranking step is kept when the candidates belong to it, and the finer step is still gated", {
  # PtCon 18S Ulva shape. Candidates sit in two genera of one family, so the
  # LCA is the family. The reference knows exactly one genus (Ulva) and, under
  # it, exactly one species (U. lactuca) -- which no candidate is.
  # family -> genus Ulva is legitimate (a candidate IS an Ulva);
  # genus -> U. lactuca is not.
  df <- make_posterior(
    observation_id = rep("ASV_3", 2),
    taxon_name = c("Ulva lobata", "Umbraulva olivascens"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean = c(0.5, 0.5),
    genus = c("Ulva", "Umbraulva"),
    family = c("Ulvaceae", "Ulvaceae")
  )
  ref <- data.frame(
    taxon_name = "Ulva lactuca", genus = "Ulva", family = "Ulvaceae",
    stringsAsFactors = FALSE
  )
  out <- suppressMessages(posterior_consensus(
    df, rank_system = c("family", "genus", "species"), species_reference = ref
  ))
  expect_equal(out$consensus_rank, "genus")
  expect_equal(out$consensus_taxon, "Ulva")
  expect_true(out$downranked)
  expect_false(out$is_resolved)

  # Ungated, the same row is relabelled all the way to a species no candidate was.
  ungated <- suppressMessages(posterior_consensus(
    df, rank_system = c("family", "genus", "species"), species_reference = ref,
    downrank_requires_candidate = FALSE
  ))
  expect_equal(ungated$consensus_taxon, "Ulva lactuca")
})

test_that("the candidate gate does not fire when plausible_taxa is empty or absent", {
  df <- make_posterior(
    observation_id = rep("ASV_4", 2),
    taxon_name = c("Sardinops caeruleus", "Sardinops ocellatus"),
    taxon_name_rank = rep("species", 2),
    hypothesis_type = rep("specific_candidate", 2),
    posterior_mean = c(0.5, 0.5),
    genus = rep("Sardinops", 2)
  )
  ref <- data.frame(taxon_name = "Sardinops sagax", genus = "Sardinops", stringsAsFactors = FALSE)
  res <- suppressMessages(posterior_consensus(
    df, rank_system = c("genus", "species"), species_reference = ref
  ))
  # plausible_taxa is populated here, so the gate DOES fire
  expect_equal(res$consensus_taxon, "Sardinops")
  # a hand-built frame with the column stripped keeps the old behaviour
  stripped <- res
  stripped$plausible_taxa <- NULL
  stripped$is_resolved <- FALSE
  stripped$consensus_taxon <- "Sardinops"
  stripped$consensus_rank <- "genus"
  ref2 <- TaxaAssign:::.build_species_ref(ref, c("genus", "species"))
  out <- TaxaAssign:::.downrank_consensus(stripped, ref2, c("genus", "species"))
  expect_equal(out$consensus_taxon, "Sardinops sagax")
})


# ===========================================================================
# prior_branch + the evidence gate
# ===========================================================================

.branch_post <- function(branch, eff = NA_real_) {
  data.frame(
    observation_id = "o1",
    taxon_name = "Aus bus",
    taxon_name_rank = "species",
    hypothesis_type = "specific_candidate",
    genus = "Aus", family = "Aidae", species = "Aus bus",
    posterior_mean = 1, posterior_point_est = 1,
    prior_branch = branch,
    effective_records = eff,
    stringsAsFactors = FALSE
  )
}

test_that("kernel_estimated counts as an occurrence record", {
  new <- posterior_consensus(.branch_post("kernel_estimated", 100), min_posterior = 0)
  expect_true(new$winner_has_occurrence_record)
})

test_that("an unrecognised prior_branch value stops, naming the value and the accepted set", {
  # 1.0 has no predecessor: a pre-1.0 label on a cached prior table (e.g. the
  # retired "resident_observed" alias) must error, not be silently read as
  # "not a kernel-estimated row".
  bad <- .branch_post("resident_observed", 100)
  err <- tryCatch(
    posterior_consensus(bad, min_posterior = 0),
    error = function(e) e
  )
  expect_s3_class(err, "error")
  expect_match(conditionMessage(err), "resident_observed", fixed = TRUE)
  expect_match(conditionMessage(err), "kernel_estimated", fixed = TRUE)
})

test_that("a non-kernel branch still reads FALSE", {
  for (b in c("resident_undetected", "transport")) {
    out <- posterior_consensus(.branch_post(b, 100), min_posterior = 0)
    expect_false(out$winner_has_occurrence_record)
  }
})

test_that("min_effective_records defaults to 0, i.e. no behaviour change", {
  # The whole point of the default: the rename is truthful, not behavioural.
  thin <- .branch_post("kernel_estimated", 0.0001)
  expect_true(posterior_consensus(thin, min_posterior = 0)$winner_has_occurrence_record)
})

test_that("min_effective_records gates a thin row when asked to", {
  thin <- .branch_post("kernel_estimated", 0.0001)
  rich <- .branch_post("kernel_estimated", 3663)
  expect_false(
    posterior_consensus(thin, min_posterior = 0,
                        min_effective_records = 1)$winner_has_occurrence_record
  )
  expect_true(
    posterior_consensus(rich, min_posterior = 0,
                        min_effective_records = 1)$winner_has_occurrence_record
  )
})

test_that("min_effective_records > 0 with no effective_records column is an error", {
  # A prior table missing effective_records cannot answer the evidence-gate
  # question at all; silently leaving the branch verdict standing would
  # misrepresent an unanswerable check as a passed one.
  no_eff <- .branch_post("kernel_estimated")
  no_eff$effective_records <- NULL
  expect_error(
    posterior_consensus(no_eff, min_posterior = 0, min_effective_records = 1),
    "effective_records"
  )
})

test_that("min_effective_records is validated", {
  p <- .branch_post("kernel_estimated", 1)
  expect_error(posterior_consensus(p, min_effective_records = -1), "non-negative")
  expect_error(posterior_consensus(p, min_effective_records = NA), "non-negative")
  expect_error(posterior_consensus(p, min_effective_records = c(1, 2)), "non-negative")
})

# ==============================================================================
# unreferenced_taxonomy_lookup: a failed lookup never passes for "not found"
# ==============================================================================

test_that("unreferenced_taxonomy_lookup separates matched, not_found and lookup_failed", {
  df <- make_posterior(
    observation_id = c("s1", "s2", "s3", "s4"),
    taxon_name = c("Aa bb", "Cc dd", "Gg hh", "Ee ff"),
    taxon_name_rank = "species",
    hypothesis_type = c("unreferenced_species", "unreferenced_species",
                        "specific_candidate", "unreferenced_species"),
    posterior_mean = 1,
    genus = c(NA, NA, "Gg", NA), species = c("Aa bb", "Cc dd", "Gg hh", "Ee ff")
  )
  seen_cache <- "unset"
  local_mocked_bindings(
    verify_taxon_names = function(name_list, backbone_id, cache_dir = NULL, ...) {
      seen_cache <<- cache_dir
      data.frame(
        user_supplied_name = name_list,
        matched_name = ifelse(name_list == "Aa bb", "Aa bb", NA),
        classification_path = ifelse(name_list == "Aa bb", "Aa|Aa bb", NA),
        classification_ranks = ifelse(name_list == "Aa bb", "genus|species", NA),
        verified = name_list != "Cc dd",
        matched = name_list == "Aa bb",
        stringsAsFactors = FALSE
      )
    },
    .package = "TaxaTools"
  )
  expect_message(
    out <- suppressWarnings(posterior_consensus(df,
      rank_system = c("genus", "species"), lookup_missing_taxonomy = TRUE,
      backbone_id = 11L, taxonomy_cache_dir = "somewhere"
    )),
    "lookup FAILED for 1 of 3"
  )
  st <- stats::setNames(out$unreferenced_taxonomy_lookup, out$observation_id)
  expect_identical(unname(st[c("s1", "s2", "s3", "s4")]),
    c("matched", "lookup_failed", NA, "not_found"))
  expect_identical(seen_cache, "somewhere")
})

test_that("unreferenced_taxonomy_lookup is NA when no lookup was requested", {
  df <- make_posterior("s1", "Aa bb", "species", "unreferenced_species", 1,
    genus = NA, species = "Aa bb")
  out <- posterior_consensus(df, rank_system = c("genus", "species"))
  expect_true("unreferenced_taxonomy_lookup" %in% names(out))
  expect_true(is.na(out$unreferenced_taxonomy_lookup))
})

test_that("the lookup omits cache_dir entirely when no cache was asked for", {
  # A TaxaTools predating cache_dir must still serve the default path. If the
  # argument were passed unconditionally, that call would error and every row
  # would read lookup_failed, which looks like a service outage rather than a
  # version mismatch.
  df <- make_posterior(
    observation_id = "s1",
    taxon_name = "Aa bb",
    taxon_name_rank = "species",
    hypothesis_type = "unreferenced_species",
    posterior_mean = 1,
    genus = NA, species = "Aa bb"
  )
  seen <- NULL
  local_mocked_bindings(
    verify_taxon_names = function(name_list, backbone_id, ...) {
      seen <<- names(list(...))
      data.frame(
        user_supplied_name = name_list, matched_name = name_list,
        classification_path = "Aa|Aa bb", classification_ranks = "genus|species",
        verified = TRUE, matched = TRUE, stringsAsFactors = FALSE
      )
    },
    .package = "TaxaTools"
  )
  out <- suppressMessages(suppressWarnings(posterior_consensus(df,
    rank_system = c("genus", "species"), lookup_missing_taxonomy = TRUE,
    backbone_id = 11L
  )))
  expect_false("cache_dir" %in% seen)
  expect_true(all(out$unreferenced_taxonomy_lookup %in% c("matched", NA)))
})


test_that("a verify_taxon_names() error marks every looked-up observation lookup_failed", {
  df <- make_posterior(c("s1", "s2"), c("Aa bb", "Cc dd"), "species",
    "unreferenced_species", 1, genus = NA, species = c("Aa bb", "Cc dd"))
  local_mocked_bindings(verify_taxon_names = function(...) stop("HTTP 500"), .package = "TaxaTools")
  out <- suppressMessages(suppressWarnings(posterior_consensus(df,
    rank_system = c("genus", "species"), lookup_missing_taxonomy = TRUE, backbone_id = 11L)))
  expect_identical(out$unreferenced_taxonomy_lookup, c("lookup_failed", "lookup_failed"))
})

test_that("a blank species value is missing, not a unanimous species named ''", {
  # A family-level generic row whose species/genus are "" (reference
  # taxonomies store an absent rank either way), next to two congeners.
  # The plausible set is two family-level rows (as when a generic row was
  # repeated upstream) whose blank species values "agree" with each other.
  df <- data.frame(
    observation_id = "O1",
    taxon_name = c("Rhodomelaceae", "Rhodomelaceae", "Neosiphonia yendoi"),
    taxon_name_rank = c("family", "family", "species"),
    hypothesis_type = c("unreferenced_genus", "unreferenced_genus", "specific_candidate"),
    family = "Rhodomelaceae",
    genus = c("", "", "Neosiphonia"),
    species = c("", "", "Neosiphonia yendoi"),
    prior_mean = 0.1, score_likelihood = 1,
    posterior_point_est = c(0.48, 0.48, 0.04),
    posterior_mean = c(0.48, 0.48, 0.04),
    stringsAsFactors = FALSE
  )
  out <- suppressMessages(posterior_consensus(df,
    rank_system = c("family", "genus", "species"),
    lookup_missing_taxonomy = FALSE
  ))
  expect_false(identical(out$consensus_taxon, ""))
  expect_false(identical(out$consensus_rank, "species"))
  expect_equal(out$consensus_taxon, "Rhodomelaceae")
})

# ---- Tail pooling below min_posterior ----------------------------------------

.tail_df <- function(win_post, tail_posts, tail_genus = "Littorina", tail_family = "Littorinidae") {
  n <- length(tail_posts)
  sp <- paste(tail_genus, paste0("sp", seq_len(n)))
  data.frame(
    observation_id = "O1",
    taxon_name = c("Littorina littorea", sp),
    taxon_name_rank = "species",
    hypothesis_type = "specific_candidate",
    family = c("Littorinidae", rep(tail_family, n)),
    genus = c("Littorina", rep(tail_genus, n)),
    species = c("Littorina littorea", sp),
    prior_mean = 0.1, score_likelihood = 1,
    posterior_point_est = c(win_post, tail_posts),
    posterior_mean = c(win_post, tail_posts),
    stringsAsFactors = FALSE
  )
}

test_that("a lone survivor beside a flat tail is not a species call", {
  # 0.13 survivor; twenty hypotheses at 0.0435 each (all below 0.05)
  df <- .tail_df(0.13, rep(0.87 / 20, 20), tail_genus = "Lacuna")
  out <- suppressMessages(posterior_consensus(df, rank_system = c("family", "genus", "species"), pool_tail = TRUE))
  expect_equal(out$consensus_rank, "family")
  expect_equal(out$consensus_taxon, "Littorinidae")
  expect_true(out$tail_pooled)
  expect_equal(out$tail_mass, 0.87, tolerance = 1e-9)
  expect_equal(out$consensus_posterior, 1, tolerance = 1e-9)
})

test_that("a tail within the survivor's genus coarsens only to genus", {
  df <- .tail_df(0.13, rep(0.87 / 20, 20), tail_genus = "Littorina")
  out <- suppressMessages(posterior_consensus(df, rank_system = c("family", "genus", "species"), pool_tail = TRUE))
  expect_equal(out$consensus_rank, "genus")
  expect_equal(out$consensus_taxon, "Littorina")
})

test_that("a confident call is unchanged and does not pool the tail", {
  df <- .tail_df(0.95, c(0.03, 0.02), tail_genus = "Lacuna")
  out <- suppressMessages(posterior_consensus(df, rank_system = c("family", "genus", "species"), pool_tail = TRUE))
  expect_equal(out$consensus_rank, "species")
  expect_equal(out$consensus_taxon, "Littorina littorea")
  expect_false(out$tail_pooled)
  expect_equal(out$tail_mass, 0.05, tolerance = 1e-9)
})

test_that("with no hypothesis above min_posterior the tail is the plausible set", {
  df <- .tail_df(0.04, rep(0.96 / 24, 24), tail_genus = "Lacuna")
  out <- suppressMessages(suppressWarnings(
    posterior_consensus(df, rank_system = c("family", "genus", "species"), pool_tail = TRUE)
  ))
  expect_equal(out$consensus_taxon, "Littorinidae")
  expect_true(out$tail_pooled)
})

test_that("by default the tail is discarded as before, but its mass is reported", {
  df <- .tail_df(0.13, rep(0.87 / 20, 20), tail_genus = "Lacuna")
  out <- suppressMessages(posterior_consensus(df, rank_system = c("family", "genus", "species")))
  expect_equal(out$consensus_taxon, "Littorina littorea")
  expect_false(out$tail_pooled)
  expect_equal(out$tail_mass, 0.87, tolerance = 1e-9)
})

test_that("pool_tail must be TRUE or FALSE", {
  df <- .tail_df(0.95, c(0.03, 0.02))
  expect_error(posterior_consensus(df, pool_tail = NA), "pool_tail")
})

# ---- consensus_method = "credible_node" ------------------------------------
.cn_df <- function() {
  data.frame(
    observation_id = "E1",
    taxon_name = c("Oligocottus snyderi", paste("Oligocottus", c("a", "b", "c", "d", "e")), "Clinocottus analis"),
    taxon_name_rank = "species", hypothesis_type = "specific_candidate",
    order = "Perciformes",
    family = c(rep("Cottidae", 6), "Psychrolutidae"),
    genus = c(rep("Oligocottus", 6), "Clinocottus"),
    posterior_point_est = c(0.80, rep(0.03, 5), 0.05), stringsAsFactors = FALSE
  )
}
.cn <- function(df, ...) suppressWarnings(suppressMessages(posterior_consensus(df,
  rank_system = c("order", "family", "genus", "species"), ...)))

test_that("credible_node reports the finest taxon holding the threshold", {
  out <- .cn(.cn_df(), consensus_method = "credible_node")
  expect_equal(out$consensus_taxon, "Oligocottus")
  expect_equal(out$consensus_rank, "genus")
  expect_equal(out$consensus_reason, "credible_node")
  expect_equal(out$consensus_posterior, 0.95, tolerance = 1e-9)
})

test_that("credible_node counts rows named at coarser ranks toward their own taxon", {
  df <- data.frame(
    observation_id = "E1",
    taxon_name = c("Balticina finmarchica", "Balticina", "Balticinidae", "Scleralcyonacea"),
    taxon_name_rank = c("species", "genus", "family", "order"),
    hypothesis_type = c("specific_candidate", "unreferenced_species", "unreferenced_genus", "unreferenced_family"),
    order = "Scleralcyonacea", family = c(rep("Balticinidae", 3), NA),
    genus = c("Balticina", "Balticina", NA, NA),
    posterior_point_est = c(0.05, 0.10, 0.30, 0.55), stringsAsFactors = FALSE
  )
  out <- .cn(df, consensus_method = "credible_node")
  # family holds 0.45; only the order holds >= 0.9
  expect_equal(out$consensus_taxon, "Scleralcyonacea")
  expect_equal(out$consensus_rank, "order")
})

test_that("credible_node is unresolved when unnamed mass keeps every taxon below the threshold", {
  df <- .cn_df()
  df <- rbind(df, transform(df[1, ], taxon_name = NA, taxon_name_rank = NA,
    hypothesis_type = "unreferenced_genus", order = NA, family = NA, genus = NA,
    posterior_point_est = 0.2))
  out <- .cn(df, consensus_method = "credible_node")
  expect_true(is.na(out$consensus_taxon))
  expect_equal(out$consensus_reason, "no_credible_node")
})

test_that("the default consensus_method is lca and unchanged", {
  expect_identical(.cn(.cn_df()), .cn(.cn_df(), consensus_method = "lca"))
})

test_that("a genus-rank row carrying its anchor's species value is not counted as that species", {
  df <- data.frame(
    observation_id = "E1",
    taxon_name = c("Garveia", "Garveia grisea", "Garveia sp. CC-2005"),
    taxon_name_rank = c("genus", "species", "species"),
    hypothesis_type = c("unreferenced_species", "specific_candidate", "specific_candidate"),
    family = "Bougainvilliidae", genus = "Garveia",
    species = c("Garveia sp. CC-2005", "Garveia grisea", "Garveia sp. CC-2005"),
    posterior_point_est = c(0.934, 0.022, 0.044), stringsAsFactors = FALSE
  )
  rs <- c("family", "genus", "species")
  cn <- suppressWarnings(suppressMessages(posterior_consensus(df, rank_system = rs, consensus_method = "credible_node")))
  expect_equal(cn$consensus_taxon, "Garveia")
  expect_equal(cn$consensus_rank, "genus")
  lc <- suppressWarnings(suppressMessages(posterior_consensus(df, rank_system = rs, pool_tail = TRUE)))
  expect_equal(lc$consensus_taxon, "Garveia")
})

# ---- likelihood-only consensus and prior_role ------------------------------
.pd_df <- function(lik, prior, taxa = c("Littorina keenae", "Littorina scutulata"),
                   rank = "species") {
  pt <- lik * prior / sum(lik * prior)
  data.frame(
    observation_id = "E1", taxon_name = taxa, taxon_name_rank = rank,
    hypothesis_type = "specific_candidate", family = "Littorinidae",
    genus = "Littorina", score_likelihood = lik, prior_mean = prior,
    posterior_point_est = pt, stringsAsFactors = FALSE
  )
}
.pd_run <- function(df, ...) {
  suppressMessages(posterior_consensus(df,
    rank_system = c("family", "genus", "species"), ...
  ))
}

test_that("equal likelihoods split by the prior are prior-decided (narrowed)", {
  out <- .pd_run(.pd_df(lik = c(1, 1), prior = c(0.2, 0.001)))
  expect_equal(out$consensus_taxon, "Littorina keenae")
  expect_equal(out$likelihood_consensus_taxon, "Littorina")
  expect_equal(out$likelihood_consensus_rank, "genus")
  expect_equal(out$prior_role, "narrowed")
})

test_that("a call the likelihoods already make is not prior-decided", {
  out <- .pd_run(.pd_df(lik = c(1, 0.001), prior = c(0.01, 0.01)))
  expect_equal(out$consensus_taxon, "Littorina keenae")
  expect_equal(out$likelihood_consensus_taxon, "Littorina keenae")
  expect_equal(out$prior_role, "agrees")
})

test_that("a prior that overturns the likelihood winner is 'changed'", {
  out <- .pd_run(.pd_df(lik = c(1, 0.01), prior = c(1e-6, 0.5)))
  expect_equal(out$consensus_taxon, "Littorina scutulata")
  expect_equal(out$likelihood_consensus_taxon, "Littorina keenae")
  expect_equal(out$prior_role, "changed")
})

test_that("a prior that spreads mass to a coarser call is 'broadened', not decided", {
  out <- .pd_run(.pd_df(lik = c(1, 0.02), prior = c(0.01, 0.6)))
  expect_equal(out$likelihood_consensus_taxon, "Littorina keenae")
  expect_equal(out$consensus_taxon, "Littorina")
  expect_equal(out$prior_role, "broadened")
})

test_that("likelihood_consensus = FALSE, or no score_likelihood, leaves NA columns", {
  off <- .pd_run(.pd_df(lik = c(1, 1), prior = c(0.2, 0.001)), likelihood_consensus = FALSE)
  expect_true(is.na(off$prior_role))
  expect_false("prior_decided" %in% names(off))
  df <- .pd_df(lik = c(1, 1), prior = c(0.2, 0.001))
  df$score_likelihood <- NULL
  nolik <- .pd_run(df)
  expect_true(all(c("likelihood_consensus_taxon", "likelihood_support") %in% names(nolik)))
  expect_true(is.na(nolik$likelihood_support))
})

test_that("the likelihood pass leaves every other column unchanged", {
  df <- .pd_df(lik = c(1, 1), prior = c(0.2, 0.001))
  on <- .pd_run(df)
  off <- .pd_run(df, likelihood_consensus = FALSE)
  new_cols <- c("likelihood_consensus_taxon", "likelihood_consensus_rank", "prior_role", "likelihood_support")
  expect_identical(on[, setdiff(names(on), new_cols)], off[, setdiff(names(off), new_cols)])
})

test_that("a complement row the prior already discounts does not move prior_role", {
  lik <- c(1, 0.05, 0.9)
  prior <- c(0.01, 0.01, 1e-6)
  pt <- lik * prior / sum(lik * prior)
  df <- data.frame(
    observation_id = "E1",
    taxon_name = c("Littorina keenae", "Littorina scutulata", "Littorina"),
    taxon_name_rank = c("species", "species", "genus"),
    hypothesis_type = c("specific_candidate", "specific_candidate", "unreferenced_species"),
    family = "Littorinidae", genus = "Littorina",
    score_likelihood = lik, prior_mean = prior, posterior_point_est = pt,
    stringsAsFactors = FALSE
  )
  out <- suppressMessages(posterior_consensus(df, rank_system = c("family", "genus", "species")))
  expect_equal(out$consensus_taxon, "Littorina keenae")
  # under a uniform baseline the genus row (lik 0.9) would win and every call
  # would read prior-decided; flattening only the named candidates does not
  expect_equal(out$prior_role, "agrees")
})

test_that("likelihood_support is the reported taxon's share under the flattened-prior baseline", {
  lik <- c(1, 0.19); prior <- c(4.6e-3, 2.2e-3)
  df <- data.frame(observation_id = "E1", taxon_name = c("Rhacochilus vacca", "Rhacochilus toxotes"),
    taxon_name_rank = "species", hypothesis_type = "specific_candidate",
    family = "Embiotocidae", genus = "Rhacochilus", score_likelihood = lik, prior_mean = prior,
    posterior_point_est = lik * prior / sum(lik * prior), stringsAsFactors = FALSE)
  out <- suppressMessages(posterior_consensus(df, rank_system = c("family", "genus", "species")))
  expect_equal(out$consensus_taxon, "Rhacochilus vacca")
  expect_equal(out$likelihood_support, 1 / 1.19, tolerance = 1e-9)
  expect_equal(out$prior_role, "narrowed")
})


# ---- robust credible node (imprecise prior, robust_prior_s) ------------------
.rb_df <- function(lik, prior, N) {
  data.frame(observation_id = "E1",
    taxon_name = c("Rhacochilus vacca", "Rhacochilus toxotes"), taxon_name_rank = "species",
    hypothesis_type = "specific_candidate", family = "Embiotocidae", genus = "Rhacochilus",
    score_likelihood = lik, prior_mean = prior, prior_alpha = prior * N, prior_beta = (1 - prior) * N,
    prior_branch = "kernel_estimated",
    posterior_point_est = lik * prior / sum(lik * prior), stringsAsFactors = FALSE)
}
.rb <- function(df, ...) suppressMessages(posterior_consensus(df,
  rank_system = c("family", "genus", "species"), consensus_method = "credible_node",
  likelihood_consensus = FALSE, ...))

test_that("a call resting on a thinly supported prior coarsens; off restores it", {
  # equal likelihoods, prior 0.97 vs 0.03 from few records (N = 30)
  df <- .rb_df(c(1, 1), c(0.0097, 0.0003), N = 30)
  on <- .rb(df)
  off <- .rb(df, robust_prior_s = 0)
  expect_equal(off$consensus_taxon, "Rhacochilus vacca")
  expect_equal(on$consensus_taxon, "Rhacochilus")
  expect_equal(on$consensus_rank, "genus")
  expect_true(is.na(off$robust_lower_posterior))
})

test_that("a call the sequence decides is unaffected by the robust rule", {
  df <- .rb_df(c(1, 1e-4), c(0.005, 0.005), N = 30)
  on <- .rb(df)
  expect_equal(on$consensus_taxon, "Rhacochilus vacca")
  expect_gte(on$robust_lower_posterior, 0.9)
})

test_that("a prior from many records survives the robust rule", {
  df <- .rb_df(c(1, 1), c(0.0097, 0.0003), N = 1e6)
  expect_equal(.rb(df)$consensus_taxon, "Rhacochilus vacca")
})

test_that("robust_prior_s is validated", {
  expect_error(.rb(.rb_df(c(1, 1), c(0.5, 0.5), 10), robust_prior_s = -1), "non-negative")
})

# ---- credible node on per-row (rank, name) ancestry ---------------------------
.anc <- function(df, ...) suppressWarnings(suppressMessages(posterior_consensus(df,
  rank_system = c("phylum", "class", "order", "family", "genus", "species"),
  consensus_method = "credible_node", likelihood_consensus = FALSE, robust_prior_s = 0, ...)))
.anc_df <- function(post, class, order, family = c("F1", "F2", "F3"), genus = c("G1", "G2", "G3")) {
  data.frame(observation_id = "E1", taxon_name = paste(genus, c("a", "b", "c")),
    taxon_name_rank = "species", hypothesis_type = "specific_candidate",
    phylum = "Chordata", class = class, order = order, family = family, genus = genus,
    posterior_point_est = post, stringsAsFactors = FALSE)
}

test_that("a row lacking a rank stays in the denominator as a non-member", {
  # class known for 0.6 of the mass, missing for 0.4: Actinopteri holds 0.6,
  # not 0.6 / 0.6, so no class call; the phylum carries every row
  df <- .anc_df(c(0.3, 0.3, 0.4), class = c("Actinopteri", "Actinopteri", NA),
    order = c("O1", "O2", "O3"))
  out <- .anc(df)
  expect_equal(out$consensus_taxon, "Chordata")
  expect_equal(out$consensus_rank, "phylum")
  expect_equal(out$consensus_limit, "backbone")
  # unnamed rows count too
  df2 <- rbind(.anc_df(c(0.5, 0.45, 0), class = "C1", order = "O1"),
    transform(.anc_df(0.05, "C1", "O1")[1, ], taxon_name = NA, taxon_name_rank = NA))
  expect_equal(.anc(df2)$consensus_rank, "order") # 0.95 named / 1.0 total, genus split
  df2$posterior_point_est[4] <- 0.2
  df2$posterior_point_est[1:2] <- c(0.4, 0.4)
  expect_true(is.na(.anc(df2)$consensus_taxon)) # 0.8 of 1.0: nothing credible
})

test_that("ragged lineages: each row feeds only the ancestors it carries", {
  # row A: order O1, no class. row B: class C1, no order. Neither is
  # imputed from the other, so neither order O1 nor class C1 holds A + B.
  df <- .anc_df(c(0.5, 0.45, 0.05), class = c(NA, "C1", "C1"), order = c("O1", NA, "O1"))
  out <- .anc(df)
  expect_equal(out$consensus_rank, "phylum")
  expect_equal(out$consensus_limit, "backbone")
  # the same posteriors with complete lineages give the order call
  full <- .anc_df(c(0.5, 0.45, 0.05), class = "C1", order = "O1")
  expect_equal(.anc(full)$consensus_taxon, "O1")
  expect_equal(.anc(full)$consensus_limit, "threshold")
})

test_that("consensus_limit separates threshold-limited from backbone-limited calls", {
  # complete lineages, mass spread across two genera: threshold-limited
  spread <- .anc_df(c(0.5, 0.48, 0.02), class = "C1", order = "O1", family = "F1")
  out <- .anc(spread)
  expect_equal(out$consensus_taxon, "F1")
  expect_equal(out$consensus_limit, "threshold")
  # a species call is not coarse
  sp <- .anc_df(c(0.97, 0.02, 0.01), class = "C1", order = "O1")
  expect_true(is.na(.anc(sp)$consensus_limit))
  # a hypothesis named at family has no genus by design, not a lineage gap
  ring <- .anc_df(c(0.5, 0.48, 0.02), class = "C1", order = "O1", family = "F1")
  ring$taxon_name[2] <- "F1"; ring$taxon_name_rank[2] <- "family"; ring$genus[2] <- NA
  ring$hypothesis_type[2] <- "unreferenced_genus"
  expect_equal(.anc(ring)$consensus_limit, "threshold")
  # lca method leaves the column NA
  expect_true(is.na(suppressWarnings(suppressMessages(posterior_consensus(spread,
    rank_system = c("family", "genus", "species"), likelihood_consensus = FALSE)))$consensus_limit))
})

test_that("the robust rule stamps a call it coarsened", {
  df <- .rb_df(c(1, 1), c(0.0097, 0.0003), N = 30)
  expect_equal(.rb(df)$consensus_limit, "robust_prior")
})

test_that("robust N never comes from floor or dark-diversity pseudo-counts", {
  # all candidates unrecorded (floor rows, alpha + beta = 4): no record count,
  # so the plain rule applies rather than eps = 1/5
  df <- .rb_df(c(1, 0.05), c(2.5e-6, 2.5e-6), N = 4)
  df$prior_branch <- "resident_undetected"
  out <- .rb(df)
  expect_equal(out$consensus_taxon, "Rhacochilus vacca")
  expect_true(is.na(out$robust_lower_posterior))
  # the site's record count, when supplied, is used instead
  df$prior_site_records <- 3e5
  out2 <- .rb(df)
  expect_false(is.na(out2$robust_lower_posterior))
  # and it overrides the observation's own kernel rows
  k <- .rb_df(c(1, 1), c(0.0097, 0.0003), N = 1e6) # survives at N = 1e6
  k$prior_site_records <- 30 # but the site has only 30 records
  expect_equal(.rb(k)$consensus_taxon, "Rhacochilus")
})

# ---- lineage_conflict, threshold > 0.5, rank order (2026-10-02) --------------
.lc <- function(df, ...) suppressWarnings(suppressMessages(posterior_consensus(df,
  rank_system = c("phylum", "class", "order", "family", "genus", "species"),
  consensus_method = "credible_node", likelihood_consensus = FALSE, robust_prior_s = 0, ...)))

test_that("lineage_conflict reports a name the rows use with two lineages", {
  h <- data.frame(observation_id = "E1", taxon_name = c("Porella aaa", "Porella bbb"),
    taxon_name_rank = "species", hypothesis_type = "specific_candidate",
    phylum = c("Bryozoa", "Marchantiophyta"), class = c("Gymnolaemata", "Jungermanniopsida"),
    order = c("Cheilostomatida", "Porellales"), family = c("Bryocryptellidae", "Porellaceae"),
    genus = "Porella", posterior_point_est = c(0.5, 0.5), stringsAsFactors = FALSE)
  out <- .lc(h)
  expect_true("lineage_conflict" %in% names(out))
  expect_equal(out$lineage_conflict, "genus:Porella")
  # reported only: the call itself is unchanged by the diagnostic (with the
  # cross-phylum rule off; by default that rule withholds this pooled call,
  # whose two rows sit in different phyla)
  expect_equal(.lc(h, cross_phylum_eps = 0)$consensus_taxon, "Porella")
  expect_equal(.lc(h, cross_phylum_eps = 0)$lineage_conflict, "genus:Porella")
  expect_true(is.na(out$consensus_taxon))
  expect_equal(out$consensus_limit, "cross_phylum")
  ok <- transform(h, phylum = "Bryozoa", class = "Gymnolaemata", order = "Cheilostomatida",
    family = "Bryocryptellidae")
  expect_true(is.na(.lc(ok)$lineage_conflict))
})

test_that("credible_node refuses a threshold at or below one half", {
  df <- data.frame(observation_id = "E1", taxon_name = c("Aaa x", "Bbb y"), taxon_name_rank = "species",
    hypothesis_type = "specific_candidate", phylum = "P", class = "C", order = "O",
    family = c("F1", "F2"), genus = c("Aaa", "Bbb"), posterior_point_est = c(0.5, 0.5),
    stringsAsFactors = FALSE)
  expect_error(.lc(df, cumulative_threshold = 0.5), "exceed 0.5")
  # the lca method is unchanged
  expect_no_error(suppressWarnings(suppressMessages(posterior_consensus(df,
    rank_system = c("family", "genus", "species"), cumulative_threshold = 0.5, likelihood_consensus = FALSE))))
})

test_that("a non-standard rank in rank_system orders the rank masking", {
  # row B is named at subgenus but carries its anchor's species in `species`:
  # it must not count toward that species
  df <- data.frame(observation_id = "E1", taxon_name = c("Aaa bbb", "Aaa (Sub)"),
    taxon_name_rank = c("species", "subgenus"), hypothesis_type = c("specific_candidate", "unreferenced_species"),
    family = "F1", genus = "Aaa", subgenus = c(NA, "Aaa (Sub)"), species = c("Aaa bbb", "Aaa bbb"),
    posterior_point_est = c(0.5, 0.5), stringsAsFactors = FALSE)
  out <- suppressWarnings(suppressMessages(posterior_consensus(df,
    rank_system = c("family", "genus", "subgenus", "species"), consensus_method = "credible_node",
    likelihood_consensus = FALSE, robust_prior_s = 0)))
  expect_equal(out$consensus_taxon, "Aaa")
  expect_equal(out$consensus_rank, "genus")
})

# ---- consensus_limit = "rank_not_supplied" (2026-10-03) ---------------------
test_that("a rank no row carries is 'rank_not_supplied'; a rank some lineages lack stays 'backbone'", {
  rs <- c("phylum", "class", "order", "family", "genus", "species")
  base <- data.frame(observation_id = "E1", taxon_name = c("Aaa x", "Bbb y", "Ccc z"),
    taxon_name_rank = "species", hypothesis_type = "specific_candidate", phylum = "Chordata",
    order = c("Perciformes", "Perciformes", "Gadiformes"), family = c("F1", "F2", "F3"),
    genus = c("Aaa", "Bbb", "Ccc"), posterior_point_est = c(0.45, 0.4, 0.15), stringsAsFactors = FALSE)
  pc <- function(df) suppressWarnings(posterior_consensus(df, rank_system = rs,
    consensus_method = "credible_node", likelihood_consensus = FALSE, robust_prior_s = 0))
  # A: class column absent from the input
  expect_message(a <- pc(base), "\"class\".*no row of posterior_df carries")
  expect_equal(a$consensus_taxon, "Chordata")
  expect_equal(a$consensus_limit, "rank_not_supplied")
  # B: class supplied in the input, but missing from these rows' lineages
  b <- rbind(transform(base, class = NA_character_),
    transform(base[1, ], observation_id = "E2", class = "Actinopteri", posterior_point_est = 1))
  bo <- suppressMessages(pc(b))
  expect_equal(bo$consensus_limit[bo$observation_id == "E1"], "backbone")
  # C: class supplied on these rows
  co <- suppressMessages(pc(transform(base, class = "Actinopteri")))
  expect_equal(co$consensus_taxon, "Actinopteri")
  expect_equal(co$consensus_limit, "threshold")
})

# ---- per-observation chunks by row-index split (2026-10-06) ------------------
test_that("interleaved observation rows give the same consensus as grouped rows", {
  set.seed(9)
  mk <- function(o, k) data.frame(observation_id = o, taxon_name = paste("Gen", sample(letters, k), "sp"),
    taxon_name_rank = "species", hypothesis_type = "specific_candidate", family = "F1",
    genus = "Gen", posterior_point_est = prop.table(runif(k)), score_likelihood = runif(k),
    prior_mean = runif(k, 1e-4, 1e-2), stringsAsFactors = FALSE)
  d <- do.call(rbind, lapply(sprintf("o%02d", 1:12), function(o) mk(o, sample(2:5, 1))))
  run <- function(x) suppressWarnings(suppressMessages(posterior_consensus(x,
    rank_system = c("family", "genus", "species"), consensus_method = "credible_node")))
  grouped <- run(d)
  # interleave observations round-robin while keeping each observation's own row order
  pos <- stats::ave(seq_len(nrow(d)), d$observation_id, FUN = seq_along)
  inter_df <- d[order(pos, d$observation_id), ]
  expect_true(any(diff(match(inter_df$observation_id, unique(d$observation_id))) != 0 &
    duplicated(inter_df$observation_id))) # really interleaved
  inter <- run(inter_df)
  # same per-observation result regardless of how the rows of different observations interleave
  # compare column contents, both sides subset the same way (a column subset drops report_params)
  a1 <- as.list(inter[order(inter$observation_id), names(grouped)])
  b1 <- as.list(grouped[order(grouped$observation_id), names(grouped)])
  expect_identical(a1, b1)
})

test_that("an NA observation_id still runs (original chunking path)", {
  d <- data.frame(observation_id = c("o1", "o1", NA), taxon_name = c("A a", "B b", "C c"),
    taxon_name_rank = "species", hypothesis_type = "specific_candidate", family = "F", genus = c("A", "B", "C"),
    posterior_point_est = c(0.95, 0.05, 1), stringsAsFactors = FALSE)
  expect_no_error(suppressWarnings(suppressMessages(posterior_consensus(d, rank_system = c("family", "genus", "species")))))
})

# --- cross_phylum_eps -------------------------------------------------------
.xp_df <- function(post, phylum = c("Ochrophyta", "Oomycota"), kingdom = c("Chromista", "Chromista")) {
  data.frame(observation_id = "E1", taxon_name = c("Macrocystis pyrifera", "Phytophthora polonica"),
    taxon_name_rank = "species", hypothesis_type = "specific_candidate",
    kingdom = kingdom, phylum = phylum, class = c("Phaeophyceae", "Oomycetes"),
    order = c("Laminariales", "Peronosporales"), family = c("Laminariaceae", "Peronosporaceae"),
    genus = c("Macrocystis", "Phytophthora"), posterior_point_est = post, stringsAsFactors = FALSE)
}
.xp <- function(df, rs = c("phylum", "class", "order", "family", "genus", "species"), ...)
  suppressWarnings(suppressMessages(posterior_consensus(df, rank_system = rs,
    consensus_method = "credible_node", likelihood_consensus = FALSE, robust_prior_s = 0, ...)))

test_that("cross_phylum_eps withholds a call finer than phylum when the runner-up phylum holds eps or more", {
  df <- .xp_df(c(0.93, 0.07))
  # without the rule: a species call at 0.93 against another phylum's 0.07
  off <- .xp(df, cross_phylum_eps = 0)
  expect_equal(off$consensus_taxon, "Macrocystis pyrifera")
  expect_true(is.na(off$consensus_limit))
  on <- .xp(df) # default 0.05: the species call is withheld, the phylum call (0.93) stands
  expect_equal(on$consensus_taxon, "Ochrophyta")
  expect_equal(on$consensus_rank, "phylum")
  expect_equal(on$consensus_reason, "credible_node")
  expect_equal(on$consensus_limit, "cross_phylum")
  # below the tolerance the call stands (and the limit is not stamped)
  below <- .xp(.xp_df(c(0.96, 0.04)))
  expect_equal(below$consensus_taxon, "Macrocystis pyrifera")
  expect_true(is.na(below$consensus_limit))
  # eps is the tolerance: 0.10 lets the 0.07 runner-up through
  expect_equal(.xp(df, cross_phylum_eps = 0.10)$consensus_taxon, "Macrocystis pyrifera")
})

test_that("a two-phylum 0.92/0.08 observation keeps its phylum call and loses its class call", {
  # two species of one class split the leading phylum's 0.92, so the plain call is the class
  df <- rbind(.xp_df(c(0.46, 0.08)), .xp_df(c(0.46, 0))[1, ])
  df$taxon_name[3] <- "Nereocystis luetkeana"; df$genus[3] <- "Nereocystis"
  df$family[3] <- "Laminariaceae2"; df$order[3] <- "Laminariales2"
  off <- .xp(df, cross_phylum_eps = 0)
  expect_equal(off$consensus_taxon, "Phaeophyceae")
  expect_equal(off$consensus_rank, "class")
  on <- .xp(df)
  expect_equal(on$consensus_taxon, "Ochrophyta")
  expect_equal(on$consensus_rank, "phylum")
  expect_equal(on$consensus_limit, "cross_phylum")
  # a plain phylum call that holds the threshold is never withheld (nor stamped)
  ph <- .xp(.xp_df(c(0.92, 0.08)), rs = "phylum")
  expect_equal(ph$consensus_taxon, "Ochrophyta")
  expect_true(is.na(ph$consensus_limit))
})

test_that("cross_phylum_eps gives no call, or a shared clade above phylum, when no phylum holds the threshold", {
  # the leading class's main row carries no phylum, so no phylum reaches 0.90
  df <- rbind(.xp_df(c(0.08, 0.07)), .xp_df(c(0.85, 0))[1, ])
  df$taxon_name[3] <- "Nereocystis luetkeana"; df$phylum[3] <- NA
  off <- .xp(df, cross_phylum_eps = 0)
  expect_equal(off$consensus_taxon, "Macrocystis") # genus, 0.93
  on <- .xp(df)
  expect_true(is.na(on$consensus_taxon))
  expect_equal(on$consensus_limit, "cross_phylum")
  rs7 <- c("kingdom", "phylum", "class", "order", "family", "genus", "species")
  k <- .xp(df, rs = rs7)
  expect_equal(k$consensus_taxon, "Chromista")
  expect_equal(k$consensus_rank, "kingdom")
  expect_equal(k$consensus_limit, "cross_phylum")
})

test_that("cross_phylum_eps leaves single-phylum observations and phylum-or-coarser calls alone", {
  one <- .xp_df(c(0.93, 0.07), phylum = c("Ochrophyta", "Ochrophyta"))
  # Both attributes RECORD the call's own arguments, so two calls that differ
  # only in cross_phylum_eps necessarily differ in them even when every column
  # is identical -- which is what this test is actually asserting. Strip both.
  # (consensus_settings arrived with G5+G6; this test predates it, and the two
  # only meet after the merge.)
  nop <- function(x) { attr(x, "report_params") <- NULL
    attr(x, "consensus_settings") <- NULL; x }
  expect_identical(nop(.xp(one)), nop(.xp(one, cross_phylum_eps = 0)))
  # already above phylum (kingdom call): nothing to withhold
  k <- .xp_df(c(0.5, 0.5))
  rs7 <- c("kingdom", "phylum", "class", "order", "family", "genus", "species")
  expect_equal(.xp(k, rs = rs7)$consensus_rank, "kingdom")
  expect_identical(nop(.xp(k, rs = rs7)), nop(.xp(k, rs = rs7, cross_phylum_eps = 0)))
})

test_that("cross_phylum_eps is applied AFTER downranking, not before it", {
  # Regression, 2026-10-08. Shape taken from the two CalIntertidal COI
  # sipunculan observations (COI_ESV_293811/293820 @ Jalama Beach): the
  # credible node sits exactly AT phylum, which the amendment exempts, but
  # species_reference downranking then moves the call FINER than phylum --
  # precisely what this rule exists to withhold. Deciding the exemption on the
  # pre-downranking rank let the call through: on the real data the pair came
  # out at order with consensus_limit "threshold", and on this fixture
  # downranking reaches a SPECIES call that rests on a cross-phylum choice.
  df <- data.frame(
    observation_id = "E_dr",
    taxon_name = c("Aa aa", "Ab ab", "Ba ba"),
    taxon_name_rank = "species",
    hypothesis_type = "specific_candidate",
    phylum = c("Pa", "Pa", "Pb"),
    class = c("Ca", "Cb", "Cy"),
    posterior_point_est = c(0.60, 0.31, 0.09),
    stringsAsFactors = FALSE
  )
  ref <- data.frame(taxon_name = "Aa aa", class = "Ca", phylum = "Pa",
    stringsAsFactors = FALSE)
  rs <- c("phylum", "class", "species")
  run <- function(e) suppressWarnings(suppressMessages(posterior_consensus(
    df, rank_system = rs, consensus_method = "credible_node",
    likelihood_consensus = FALSE, robust_prior_s = 0,
    species_reference = ref, cross_phylum_eps = e)))

  # phylum Pa holds 0.91 and no finer rank holds 0.90, so the credible node is
  # the phylum; the runner-up phylum Pb holds 0.09, over the 0.05 default.
  off <- run(0)
  expect_true(off$downranked)
  expect_true(match(off$consensus_rank, rs) > match("phylum", rs))
  expect_false(identical(off$consensus_limit, "cross_phylum"))

  on <- run(0.05)
  expect_equal(on$consensus_taxon, "Pa")
  expect_equal(on$consensus_rank, "phylum")
  expect_equal(on$consensus_limit, "cross_phylum")
  expect_false(on$downranked)
  expect_false(on$is_resolved)
  # the flag that carries this across the downranking step is internal
  expect_false(".cross_phylum_pending" %in% names(on))
})

test_that("cross_phylum_eps is applied in the robust-prior path too", {
  df <- .xp_df(c(0.93, 0.07))
  df$score_likelihood <- c(0.93, 0.07); df$prior_mean <- 0.5
  df$prior_alpha <- 5e4; df$prior_beta <- 5e4; df$prior_site_records <- 1e5
  r <- function(e) suppressWarnings(suppressMessages(posterior_consensus(df,
    rank_system = c("phylum", "class", "order", "family", "genus", "species"),
    consensus_method = "credible_node", likelihood_consensus = FALSE, robust_prior_s = 1, cross_phylum_eps = e)))
  expect_equal(r(0)$consensus_taxon, "Macrocystis pyrifera")
  expect_equal(r(0.05)$consensus_limit, "cross_phylum")
  expect_equal(r(0.05)$consensus_taxon, "Ochrophyta")
  expect_true(is.finite(r(0.05)$robust_lower_posterior))
})

test_that("the likelihood-only pass uses the same cross-phylum rule", {
  df <- .xp_df(c(0.93, 0.07))
  df$score_likelihood <- c(0.93, 0.07); df$prior_mean <- 0.5
  run <- function(e) suppressWarnings(suppressMessages(posterior_consensus(df,
    rank_system = c("phylum", "class", "order", "family", "genus", "species"),
    consensus_method = "credible_node", likelihood_consensus = TRUE, robust_prior_s = 0, cross_phylum_eps = e)))
  expect_equal(run(0)$likelihood_consensus_taxon, "Macrocystis pyrifera")
  expect_equal(run(0.05)$likelihood_consensus_taxon, "Ochrophyta")
})

test_that("cross_phylum_eps is validated and says when it cannot apply", {
  df <- .xp_df(c(0.93, 0.07))
  for (bad in list(-0.1, 0.5, NA_real_, c(0.05, 0.1), "0.05")) {
    expect_error(.xp(df, cross_phylum_eps = bad), "cross_phylum_eps")
  }
  expect_message(suppressWarnings(posterior_consensus(df, rank_system = c("class", "order", "family", "genus", "species"),
    consensus_method = "credible_node", likelihood_consensus = FALSE, robust_prior_s = 0)),
    "cross_phylum_eps is not applied")
  expect_equal(attr(.xp(df, cross_phylum_eps = 0.1), "report_params")$cross_phylum_eps, 0.1)
})

test_that("cross_phylum_eps compares LINEAGES, not phylum name strings", {
  # Invented names throughout. mp stands in for the backbone map that
  # .phylum_lineage_map() builds from verify_taxon_names(), so the logic is
  # tested without a network call or a cache.
  mp <- list(
    Pa = c("Kk", "Pa"),            # a phylum
    Cx = c("Kk", "Pa", "Cx"),      # a CLASS inside Pa, also carried as a phylum
    Pb = c("Kk", "Pb"),            # a second, genuinely distinct phylum
    Pc = c("Kk", "Pc")
  )
  sl <- function(a, b, m = mp) TaxaAssign:::.same_lineage(a, b, m)
  cpc <- function(v, m = mp, eps = 0.05) {
    TaxaAssign:::.cross_phylum_competes(sort(v, decreasing = TRUE), eps, m)
  }

  # a name on the leader's path is the same lineage, in both directions
  expect_true(sl("Cx", "Pa"))
  expect_true(sl("Pa", "Cx"))
  expect_true(sl("Pa", "Pa"))
  # two real phyla are not
  expect_false(sl("Pa", "Pb"))
  # a name the backbone cannot place is NOT the same lineage: unresolvable is
  # not evidence of sameness, so the withholding stands
  expect_false(sl("Zz", "Pa"))
  expect_false(sl("Pa", "Zz"))
  # with no map at all nothing is confirmed, which is the old name-keyed rule
  expect_false(sl("Cx", "Pa", list()))

  # one lineage carried under two names does not compete
  expect_false(cpc(c(Pa = 0.60, Cx = 0.40)))
  # ... but it did before the map existed
  expect_true(cpc(c(Pa = 0.60, Cx = 0.40), m = list()))
  # two real phyla compete
  expect_true(cpc(c(Pa = 0.92, Pb = 0.08)))
  # an unplaceable competitor competes
  expect_true(cpc(c(Pa = 0.55, Zz = 0.45)))
  # a single phylum, and a runner-up below eps, never compete
  expect_false(cpc(c(Pa = 1)))
  expect_false(cpc(c(Pa = 0.97, Pb = 0.03)))
  # three-way: same-lineage runner-up plus a real third competitor still competes
  expect_true(cpc(c(Pa = 0.50, Cx = 0.30, Pb = 0.20)))
  # ... and a third competitor below eps is ignored
  expect_false(cpc(c(Pa = 0.60, Cx = 0.38, Pb = 0.02)))
})

test_that("a lineage-confirmed competitor does not withhold the call, an unplaceable one does", {
  # A SPECIES call that holds the threshold, with a runner-up phylum over eps.
  # Pa 0.91 / Cx 0.06 / Pb 0.03: species "Aa aa" holds 0.91, so there is a call
  # finer than phylum for the rule to act on, and Cx at 0.06 clears eps = 0.05
  # while Pb at 0.03 does not.
  d <- data.frame(
    observation_id = rep("o1", 3L),
    taxon_name = c("Aa aa", "Bb bb", "Cc cc"),
    taxon_name_rank = rep("species", 3L),
    phylum = c("Pa", "Cx", "Pb"),
    class = c("Ca", "Cb", "Cy"),
    species = c("Aa aa", "Bb bb", "Cc cc"),
    posterior_point_est = c(0.91, 0.06, 0.03),
    stringsAsFactors = FALSE
  )
  rs <- c("phylum", "class", "species")
  cn <- function(e, m) TaxaAssign:::.credible_node(
    d, d$posterior_point_est, rs, threshold = 0.90,
    cross_phylum_eps = e, lineage_map = m
  )
  mp <- list(Pa = c("Kk", "Pa"), Cx = c("Kk", "Pa", "Cx"), Pb = c("Kk", "Pb"))

  # Baseline: with the rule off the call is the species node.
  base <- cn(0, mp)
  expect_identical(base$taxon, "Aa aa")
  expect_identical(base$rank, "species")

  # Name-keyed (no map): Cx clears eps, so the species call is withheld and
  # falls back to phylum Pa, which holds 0.91.
  off <- cn(0.05, list())
  expect_identical(off$limit, "cross_phylum")
  expect_identical(off$taxon, "Pa")
  expect_identical(off$rank, "phylum")

  # Lineage-aware: the backbone places Cx inside Pa, so it is not a competing
  # phylum and the species call stands, exactly as with the rule off.
  on <- cn(0.05, mp)
  expect_identical(on$taxon, "Aa aa")
  expect_identical(on$rank, "species")
  expect_false(isTRUE(on$limit == "cross_phylum"))

  # Unplaceable competitor: still withheld. Unresolvable is not sameness.
  unp <- cn(0.05, list(Pa = c("Kk", "Pa"), Pb = c("Kk", "Pb")))
  expect_identical(unp$limit, "cross_phylum")

  # Backbone disagrees with the input (the Sipuncula shape): the input would
  # nest Cx under Pa, but a backbone that makes Cx its own phylum decides, so
  # the call is withheld.
  disagree <- list(Pa = c("Kk", "Pa"), Cx = c("Kk", "Cx"), Pb = c("Kk", "Pb"))
  expect_identical(cn(0.05, disagree)$limit, "cross_phylum")

  # NOT a guarantee of "no new species": releasing a withholding restores
  # whatever node the evidence supports, which here IS a species call. It was
  # 0 new species on the CalIntertidal run because those 3 observations had no
  # species node, not because the rule cannot produce one.
  expect_identical(on$rank, "species")
})

test_that(".phylum_lineage_map degrades to an empty map instead of failing", {
  # No backbone_id: nothing can be placed, and the caller then compares names.
  expect_identical(TaxaAssign:::.phylum_lineage_map(c("Pa", "Cx"), backbone_id = NULL), list())
  # Nothing to resolve.
  expect_identical(TaxaAssign:::.phylum_lineage_map(character(0), backbone_id = 11L), list())
  expect_identical(TaxaAssign:::.phylum_lineage_map(c(NA_character_, ""), backbone_id = 11L), list())
})
