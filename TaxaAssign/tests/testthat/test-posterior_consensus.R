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
