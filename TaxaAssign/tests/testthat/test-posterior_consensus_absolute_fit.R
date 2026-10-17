# best_identity / best_identity_rank / poor_absolute_fit pass-through: a flag
# only, never a call change.

.af_post <- function(with_cols = TRUE, poor = TRUE) {
  df <- data.frame(
    observation_id = "ASV_606",
    taxon_name = c("Hypsoblennius", "Parablennius", "Hypsoblennius sordidus"),
    taxon_name_rank = c("genus", "genus", "species"),
    hypothesis_type = c("unreferenced_species", "unreferenced_species", "specific_candidate"),
    posterior_mean = c(0.998, 0.001, 0.001),
    genus = c("Hypsoblennius", "Parablennius", "Hypsoblennius"),
    family = "Blenniidae",
    stringsAsFactors = FALSE
  )
  df$posterior_point_est <- df$posterior_mean
  if (with_cols) {
    df$best_identity <- if (poor) 86.08 else 99.4
    df$best_identity_rank <- if (poor) NA_character_ else "species"
    df$poor_absolute_fit <- poor
  }
  df
}
.af_rs <- c("family", "genus", "species")

test_that("the three absolute-fit columns are passed through from the unit's rows", {
  out <- posterior_consensus(.af_post(), rank_system = .af_rs)
  expect_equal(out$best_identity, 86.08)
  expect_true(is.na(out$best_identity_rank))
  expect_type(out$best_identity_rank, "character")
  expect_true(out$poor_absolute_fit)

  good <- posterior_consensus(.af_post(poor = FALSE), rank_system = .af_rs)
  expect_equal(good$best_identity, 99.4)
  expect_identical(good$best_identity_rank, "species")
  expect_false(good$poor_absolute_fit)
})

test_that("the CALL is identical with and without the columns (flag only)", {
  with <- posterior_consensus(.af_post(TRUE), rank_system = .af_rs)
  without <- posterior_consensus(.af_post(FALSE), rank_system = .af_rs)
  expect_equal(with$consensus_taxon, "Hypsoblennius")
  drop <- c("best_identity", "best_identity_rank", "poor_absolute_fit")
  expect_equal(with[, setdiff(names(with), drop)], without[, setdiff(names(without), drop)])
  expect_true(is.na(without$best_identity))
  expect_true(is.na(without$poor_absolute_fit))
  expect_type(without$poor_absolute_fit, "logical")
})

test_that("the columns exist on the empty-consensus row too", {
  r <- .empty_consensus_row("x")
  expect_true(all(c("best_identity", "best_identity_rank", "poor_absolute_fit") %in% names(r)))
  expect_true(is.na(r$best_identity) && is.na(r$best_identity_rank) && is.na(r$poor_absolute_fit))
})
