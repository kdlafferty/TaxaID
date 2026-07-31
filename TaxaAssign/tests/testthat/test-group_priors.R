# Tests for compute_group_priors()

.priors <- function() {
  data.frame(
    taxon_name = c("Aa one", "Aa two", "Bb one", "Cc one", "Dd one"),
    theta_mean = c(0.02,     0.05,     0.10,     NA_real_,  0.01),
    stringsAsFactors = FALSE
  )
}

.taxonomy <- function() {
  data.frame(
    taxon_name = c("Aa one", "Aa two", "Bb one", "Cc one", "Dd one"),
    genus      = c("Aa",     "Aa",     "Bb",     "Cc",      NA_character_),
    family     = c("Fam1",   "Fam1",   "Fam2",   "Fam3",    "Fam1"),
    stringsAsFactors = FALSE
  )
}

test_that("sums theta_mean within each rank group", {
  out <- compute_group_priors(.priors(), .taxonomy())
  genus_aa <- out[out$rank == "genus" & out$taxon == "Aa", ]
  expect_equal(genus_aa$theta_sum, 0.07)
  expect_equal(genus_aa$n_members, 2L)

  fam1 <- out[out$rank == "family" & out$taxon == "Fam1", ]
  # Dd one has theta_mean = 0.01 but NA genus -- still contributes at family
  # rank since family is populated there.
  expect_equal(fam1$theta_sum, 0.08)
  expect_equal(fam1$n_members, 3L)
})

test_that("a taxon with NA theta_mean does not contribute and is not counted", {
  out <- compute_group_priors(.priors(), .taxonomy())
  fam3 <- out[out$rank == "family" & out$taxon == "Fam3", ]
  # Cc one has theta_mean = NA -- Fam3 should be entirely absent, not a zero row.
  expect_equal(nrow(fam3), 0L)
})

test_that("a taxon with NA at one rank is excluded from that rank only", {
  out <- compute_group_priors(.priors(), .taxonomy())
  # Dd one has NA genus -- no genus group should include it.
  genus_taxa <- out$taxon[out$rank == "genus"]
  expect_false("Dd" %in% genus_taxa)
  # but it DOES contribute at family rank (checked above).
})

test_that("theta_sum is capped at 1 as a defensive guard", {
  priors <- data.frame(taxon_name = c("X1", "X2"), theta_mean = c(0.9, 0.9))
  taxonomy <- data.frame(taxon_name = c("X1", "X2"), genus = c("G", "G"))
  out <- compute_group_priors(priors, taxonomy, rank_cols = "genus")
  expect_equal(out$theta_sum[out$taxon == "G"], 1)
})

test_that("output has rank/taxon/theta_sum/n_members columns", {
  out <- compute_group_priors(.priors(), .taxonomy())
  expect_true(all(c("rank", "taxon", "theta_sum", "n_members") %in% names(out)))
})

test_that("custom rank_cols respected", {
  out <- compute_group_priors(.priors(), .taxonomy(), rank_cols = "family")
  expect_true(all(out$rank == "family"))
  expect_false("genus" %in% out$rank)
})

test_that("stops on missing required columns", {
  expect_error(compute_group_priors("x", .taxonomy()), "must be a data frame")
  expect_error(compute_group_priors(.priors(), "x"), "must be a data frame")
  p <- .priors(); p$theta_mean <- NULL
  expect_error(compute_group_priors(p, .taxonomy()), "theta_mean")
  t <- .taxonomy(); t$genus <- NULL
  expect_error(compute_group_priors(.priors(), t), "genus")
})
