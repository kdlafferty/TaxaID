# test-generate_inat_range_evidence.R
# D6: iNat as a third evidence generator, gated on the fuzzy-match column.

library(testthat)

.make_inat <- function() {
  tibble::tibble(
    taxon_name     = c("Umbra limi", "Gasterosteus gymnurus", "Notropis texanus",
                       "Esox lucius", "Perca flavescens"),
    matched_name   = c("Umbra limi", "Gasterosteus aculeatus", "Notropis texanus",
                       "Esox lucius", NA_character_),
    name_match     = c(TRUE, FALSE, TRUE, TRUE, NA),
    in_range       = c(TRUE, TRUE, TRUE, FALSE, TRUE),
    n_observations = c(2000L, 9000L, 120L, 5000L, 8000L),
    range_status   = "in_range"
  )
}

test_that("emits rows only for in-range, well-observed, name-verified taxa", {
  out <- suppressMessages(generate_inat_range_evidence(.make_inat()))
  # Umbra limi qualifies; gymnurus fails name gate; texanus fails n_obs;
  # lucius out of range; flavescens NA name_match (unverifiable)
  expect_equal(out$taxon_name, "Umbra limi")
  expect_equal(out$weight, 0.8)
  expect_equal(out$p_conc, 1)
  expect_equal(out$source, "inat_range")
})

test_that("the fuzzy-match exclusion is reported and can be disabled", {
  expect_message(generate_inat_range_evidence(.make_inat()), "differs from the query")
  out <- suppressMessages(generate_inat_range_evidence(.make_inat(), require_name_match = FALSE))
  expect_setequal(out$taxon_name,
                  c("Umbra limi", "Gasterosteus gymnurus", "Perca flavescens"))
})

test_that("a pre-name_match inat_range table elevates nothing, with guidance", {
  old <- .make_inat()[, setdiff(names(.make_inat()), "name_match")]
  expect_message(out <- generate_inat_range_evidence(old), "no name_match")
  expect_equal(nrow(out), 0L)
})

test_that("validates inputs and returns the empty schema cleanly", {
  expect_error(generate_inat_range_evidence(data.frame(x = 1)), "inat_range")
  expect_error(generate_inat_range_evidence(.make_inat(), weight = 1.5), "weight")
  expect_error(generate_inat_range_evidence(.make_inat(), p_conc = 0), "p_conc")
  none <- .make_inat(); none$in_range <- FALSE
  out <- suppressMessages(generate_inat_range_evidence(none))
  expect_equal(nrow(out), 0L)
  expect_named(out, c("taxon_name", "weight", "p_conc", "source"))
})

test_that("evidence feeds apply_undetected_evidence end to end", {
  priors <- tibble::tibble(
    taxon_name = c(NA_character_, NA_character_), taxon_name_rank = NA_character_,
    grid_id = c(NA_character_, "Grid_A"), alpha = c(1, 0.05), beta = c(999, 1.95),
    theta_mean = c(1/1000, 0.025), theta_sd = NA_real_,
    model_tier = "tier3_undetected",
    undetected_type = c("global_floor", "singleton_mirror"),
    source_taxon_name = NA_character_, main_habitat = c(NA, "Lentic")
  )
  model_obj <- structure(list(N_total = 1000L, meta = list(habitat_col = "main_habitat")),
                         class = "biofreq_model")
  ev <- suppressMessages(generate_inat_range_evidence(.make_inat()))
  out <- suppressMessages(apply_undetected_evidence(
    priors, model_obj, ev, grid_id = "Grid_A", main_habitat = "Lentic"))
  expect_equal(out$taxon_name, "Umbra limi")
  expect_equal(out$theta_mean, 1/1000 + (0.025 - 1/1000) * 0.8, tolerance = 1e-8)
  expect_equal(out$prior_mix_w, 0.8, tolerance = 1e-8)
})
