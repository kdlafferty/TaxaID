# ---- audit_reference_coverage -----------------------------------------------
# Network tests are guarded; input validation tests are offline.

test_that("audit_reference_coverage: non-data-frame input errors", {
  expect_error(audit_reference_coverage(list()), "must be a data frame")
})

test_that("audit_reference_coverage: missing target_rank column errors", {
  df <- data.frame(species = "Aa bb", genus = "Aa", stringsAsFactors = FALSE)
  expect_error(audit_reference_coverage(df, target_rank = "family"),
               "not found in reference_df")
})

test_that("audit_reference_coverage: missing species column errors", {
  df <- data.frame(genus = "Aa", stringsAsFactors = FALSE)
  expect_error(audit_reference_coverage(df), "species.*not found")
})

test_that("audit_reference_coverage: empty groups returns empty census + unreferenced", {
  df <- data.frame(genus = NA_character_, species = "Aa bb",
                   stringsAsFactors = FALSE)
  expect_warning(audit_reference_coverage(df), "No valid groups")
  out <- suppressWarnings(audit_reference_coverage(df))
  expect_equal(nrow(out$census), 0L)
  expect_equal(length(out$unreferenced), 0L)
})

# ---- apply_coverage_constraints ---------------------------------------------

.make_likelihood_df <- function() {
  tibble::tibble(
    observation_id            = "ESV_001",
    taxon_name           = c("Hybognathus nuchalis", "Hybognathus", "Leuciscidae"),
    taxon_name_rank      = c("species", "genus", "family"),
    hypothesis_type      = c("specific_candidate", "unreferenced_species", "unreferenced_genus"),
    likelihood_point_est = c(1.0, 0.5, 0.1),
    likelihood_mean      = c(1.0, 0.5, 0.1),
    likelihood_sd        = c(0, 0, 0)
  )
}

.make_census_result <- function() {
  data.frame(
    taxon_name = "Hybognathus",
    rank       = "genus",
    status     = "complete",
    stringsAsFactors = FALSE
  )
}

test_that("apply_coverage_constraints: suppresses unreferenced_species for complete genus", {
  out <- apply_coverage_constraints(.make_likelihood_df(), .make_census_result())
  h2_row <- out[out$hypothesis_type == "unreferenced_species", ]
  expect_equal(h2_row$likelihood_point_est, 0)
  expect_equal(h2_row$likelihood_mean, 0)
  expect_equal(h2_row$constraint_applied, "census_closed_genus")
})

test_that("apply_coverage_constraints: leaves other hypotheses unchanged", {
  out <- apply_coverage_constraints(.make_likelihood_df(), .make_census_result())
  h1_row <- out[out$hypothesis_type == "specific_candidate", ]
  expect_equal(h1_row$likelihood_point_est, 1.0)
  expect_true(is.na(h1_row$constraint_applied))
})

test_that("apply_coverage_constraints: soft penalty factor applied", {
  out <- apply_coverage_constraints(.make_likelihood_df(), .make_census_result(),
                                    penalty_factor = 0.5)
  h2_row <- out[out$hypothesis_type == "unreferenced_species", ]
  expect_equal(h2_row$likelihood_point_est, 0.25)
})

test_that("apply_coverage_constraints: incomplete genus not constrained", {
  census_incomplete <- data.frame(taxon_name = "Hybognathus", rank = "genus",
                                  status = "incomplete",
                                  stringsAsFactors = FALSE)
  out <- apply_coverage_constraints(.make_likelihood_df(), census_incomplete)
  h2_row <- out[out$hypothesis_type == "unreferenced_species", ]
  expect_true(is.na(h2_row$constraint_applied))
  expect_equal(h2_row$likelihood_point_est, 0.5)
})

test_that("apply_coverage_constraints: missing census columns errors", {
  expect_error(
    apply_coverage_constraints(.make_likelihood_df(), data.frame(x = 1)),
    "missing required columns"
  )
})

test_that("apply_coverage_constraints: invalid penalty_factor errors", {
  expect_error(
    apply_coverage_constraints(.make_likelihood_df(), .make_census_result(),
                               penalty_factor = 1.5),
    "\\[0, 1\\]"
  )
})

test_that("apply_coverage_constraints: non-data-frame likelihood_df errors", {
  expect_error(
    apply_coverage_constraints(list(), .make_census_result()),
    "must be a data frame"
  )
})


# ==============================================================================
# audit_acoustic_coverage() tests
# ==============================================================================

test_that("audit_acoustic_coverage: identifies in-reference and unreferenced species", {
  plausible  <- c("Turdus migratorius", "Setophaga petechia", "Limosa fedoa")
  reference  <- c("Turdus migratorius", "Setophaga petechia", "Corvus brachyrhynchos")

  result <- suppressMessages(audit_acoustic_coverage(plausible, reference))

  expect_named(result, c("census", "unreferenced"))
  expect_s3_class(result$census, "data.frame")
  expect_equal(nrow(result$census), 3L)
  expect_true(result$census$in_reference[result$census$species == "Turdus migratorius"])
  expect_false(result$census$in_reference[result$census$species == "Limosa fedoa"])
  expect_equal(result$unreferenced, "Limosa fedoa")
})

test_that("audit_acoustic_coverage: case-insensitive matching", {
  plausible <- "Turdus migratorius"
  reference <- "TURDUS MIGRATORIUS"

  result <- suppressMessages(audit_acoustic_coverage(plausible, reference))
  expect_true(result$census$in_reference)
  expect_length(result$unreferenced, 0L)
})

test_that("audit_acoustic_coverage: all in reference returns empty unreferenced", {
  sp        <- c("Turdus migratorius", "Setophaga petechia")
  result    <- suppressMessages(audit_acoustic_coverage(sp, sp))
  expect_length(result$unreferenced, 0L)
  expect_true(all(result$census$in_reference))
})

test_that("audit_acoustic_coverage: all unreferenced when reference is disjoint", {
  plausible <- c("Limosa fedoa", "Numenius americanus")
  reference <- c("Turdus migratorius")

  result <- suppressMessages(audit_acoustic_coverage(plausible, reference))
  expect_equal(sort(result$unreferenced), sort(plausible))
  expect_true(all(result$census$unreferenced))
})

test_that("audit_acoustic_coverage: match_df annotates in_match_data", {
  plausible <- c("Turdus migratorius", "Setophaga petechia", "Limosa fedoa")
  reference <- c("Turdus migratorius", "Setophaga petechia")
  mdf <- data.frame(species = c("Turdus migratorius"), stringsAsFactors = FALSE)

  result <- suppressMessages(audit_acoustic_coverage(plausible, reference, match_df = mdf))
  expect_true(result$census$in_match_data[result$census$species == "Turdus migratorius"])
  expect_false(result$census$in_match_data[result$census$species == "Setophaga petechia"])
  expect_false(result$census$in_match_data[result$census$species == "Limosa fedoa"])
})

test_that("audit_acoustic_coverage: match_df with taxon_name column works", {
  plausible <- c("Turdus migratorius", "Setophaga petechia")
  reference <- c("Turdus migratorius", "Setophaga petechia")
  mdf <- data.frame(taxon_name = "Turdus migratorius", stringsAsFactors = FALSE)

  result <- suppressMessages(audit_acoustic_coverage(plausible, reference, match_df = mdf))
  expect_true(result$census$in_match_data[result$census$species == "Turdus migratorius"])
  expect_false(result$census$in_match_data[result$census$species == "Setophaga petechia"])
})

test_that("audit_acoustic_coverage: match_df = NULL gives NA in_match_data", {
  plausible <- c("Turdus migratorius")
  reference <- c("Turdus migratorius")

  result <- suppressMessages(audit_acoustic_coverage(plausible, reference))
  expect_true(is.na(result$census$in_match_data))
})

test_that("audit_acoustic_coverage: errors on empty plausible_species", {
  expect_error(audit_acoustic_coverage(character(0), "Turdus migratorius"),
               "non-empty character vector")
})

test_that("audit_acoustic_coverage: errors on non-character reference_species", {
  expect_error(audit_acoustic_coverage("Turdus migratorius", 1:3),
               "non-empty character vector")
})

test_that("audit_acoustic_coverage: match_df without species or taxon_name warns", {
  plausible <- "Turdus migratorius"
  reference <- "Turdus migratorius"
  mdf <- data.frame(conf = 0.9, stringsAsFactors = FALSE)

  expect_warning(
    suppressMessages(audit_acoustic_coverage(plausible, reference, match_df = mdf)),
    "no 'taxon_name' or 'species' column"
  )
})
