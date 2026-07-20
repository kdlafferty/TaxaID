# Tests for audit_inat_coverage(). No coverage existed before this session --
# this is its first regression coverage. Offline via local_mocked_bindings()
# on .inat_species_info(), matching the mocking convention already used for
# .xc_recording_count()/.xc_recordings_raw() in test-coverage.R.

fake_inat_info <- function(species_name, api_token = "") {
  info <- list(
    "Turdus migratorius"  = list(taxon_id = 1L, matched_name = "Turdus migratorius",
                                 rank = "species", n_observations = 500000L, found = TRUE),
    "Limosa fedoa"        = list(taxon_id = 2L, matched_name = "Limosa fedoa",
                                 rank = "species", n_observations = 50L, found = TRUE),
    "Nonexistent species" = list(taxon_id = NA_integer_, matched_name = NA_character_,
                                 rank = NA_character_, n_observations = NA_integer_,
                                 found = FALSE)
  )
  info[[species_name]]
}

test_that("audit_inat_coverage: species above cv_threshold is not unreferenced", {
  local_mocked_bindings(.inat_species_info = fake_inat_info, .package = "TaxaLikely")
  out <- suppressMessages(audit_inat_coverage("Turdus migratorius"))
  expect_false(out$census$unreferenced)
  expect_true(out$census$cv_model_included)
  expect_equal(length(out$unreferenced), 0L)
})

test_that("audit_inat_coverage: species below cv_threshold is unreferenced", {
  local_mocked_bindings(.inat_species_info = fake_inat_info, .package = "TaxaLikely")
  out <- suppressMessages(audit_inat_coverage("Limosa fedoa", cv_threshold = 100L))
  expect_true(out$census$unreferenced)
  expect_false(out$census$cv_model_included)
  expect_equal(out$unreferenced, "Limosa fedoa")
})

test_that("audit_inat_coverage: species not found on iNat is unreferenced", {
  local_mocked_bindings(.inat_species_info = fake_inat_info, .package = "TaxaLikely")
  out <- suppressMessages(audit_inat_coverage("Nonexistent species"))
  expect_false(out$census$in_inat)
  expect_true(out$census$unreferenced)
})

test_that("audit_inat_coverage: multiple species combine into one census", {
  local_mocked_bindings(.inat_species_info = fake_inat_info, .package = "TaxaLikely")
  out <- suppressMessages(
    audit_inat_coverage(c("Turdus migratorius", "Limosa fedoa"), cv_threshold = 100L)
  )
  expect_equal(nrow(out$census), 2L)
  expect_equal(out$unreferenced, "Limosa fedoa")
})

test_that("audit_inat_coverage: match_df annotates in_match_data via taxon_name column", {
  local_mocked_bindings(.inat_species_info = fake_inat_info, .package = "TaxaLikely")
  mdf <- data.frame(taxon_name = "Turdus migratorius", stringsAsFactors = FALSE)
  out <- suppressMessages(
    audit_inat_coverage(c("Turdus migratorius", "Limosa fedoa"), match_df = mdf)
  )
  expect_true(out$census$in_match_data[out$census$species == "Turdus migratorius"])
  expect_false(out$census$in_match_data[out$census$species == "Limosa fedoa"])
})

test_that("audit_inat_coverage: match_df = NULL gives NA in_match_data", {
  local_mocked_bindings(.inat_species_info = fake_inat_info, .package = "TaxaLikely")
  out <- suppressMessages(audit_inat_coverage("Turdus migratorius"))
  expect_true(is.na(out$census$in_match_data))
})

test_that("audit_inat_coverage: errors on empty species_list", {
  expect_error(audit_inat_coverage(character(0)), "non-empty character vector")
})

test_that("audit_inat_coverage: errors on invalid cv_threshold", {
  expect_error(audit_inat_coverage("Turdus migratorius", cv_threshold = -1),
               "non-negative integer")
})

test_that("audit_inat_coverage: no valid species names gives a message and empty result", {
  expect_message(
    out <- audit_inat_coverage("   "),
    "no valid species names"
  )
  expect_equal(nrow(out$census), 0L)
})
