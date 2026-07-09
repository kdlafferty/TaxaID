# test-dataone_preview.R
# Focused coverage for .preview_one_entity()'s data_url host-allowlist guard
# (see test-dataone_standardize.R for the underlying .is_trusted_pasta_url()
# unit tests). This does not attempt full coverage of dataone_preview.R --
# preview_dataone_occurrences() itself has no test file yet, a pre-existing
# gap noted in TaxaFetch/CLAUDE.md.

library(testthat)

.make_entity <- function(data_url) {
  list(entity_name = "test entity", data_url = data_url)
}

.make_species_mapping <- function() {
  c(scientificName = "scientificName")
}

test_that(".preview_one_entity() skips an untrusted data_url without a network call", {
  out <- TaxaFetch:::.preview_one_entity(
    entity      = .make_entity("https://evil.example.com/data.csv"),
    mapping     = .make_species_mapping(),
    meta        = list(id = "test.1.1", title = "Test dataset"),
    eml_sites   = data.frame(),
    bbox        = NULL,
    n_rows      = 5L,
    large_mb    = 50,
    assume_mbps = 10,
    dwc_map     = NULL
  )
  expect_equal(out$status, "skip")
  expect_equal(out$skip_reason, "data_url host is not a trusted PASTA/EDI host")
})

test_that(".preview_one_entity() skips a missing data_url with the pre-existing reason", {
  out <- TaxaFetch:::.preview_one_entity(
    entity      = .make_entity(NA_character_),
    mapping     = .make_species_mapping(),
    meta        = list(id = "test.1.1", title = "Test dataset"),
    eml_sites   = data.frame(),
    bbox        = NULL,
    n_rows      = 5L,
    large_mb    = 50,
    assume_mbps = 10,
    dwc_map     = NULL
  )
  expect_equal(out$status, "skip")
  expect_equal(out$skip_reason, "no data URL")
})
