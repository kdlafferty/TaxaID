# registry = on TaxaFlag's name joins. Fixtures in helper-registry.R.

test_that("compute_local_occurrence_distance(registry =): records under a synonym of the called name are counted", {
  .rg_skip(); reg <- .rg_registry()
  expect_identical(utils::tail(names(formals(compute_local_occurrence_distance)), 1L), "registry")
  occ <- data.frame(taxon_name = c("Embiotoca caryi", "Embiotoca caryi", "Embiotoca jacksoni"),
                    decimalLatitude = c(34.0, 34.1, 34.2), decimalLongitude = -119, stringsAsFactors = FALSE)
  d0 <- compute_local_occurrence_distance("Hypsurus caryi", 34, -119, occ)
  expect_identical(d0$n_local_records, 0L)   # the defect: the pool files the taxon under its synonym
  d1 <- compute_local_occurrence_distance("Hypsurus caryi", 34, -119, occ, registry = reg)
  expect_identical(d1$n_local_records, 2L)
  expect_equal(d1$dist_nearest_km, 0, tolerance = 1e-9)
  expect_identical(d1$taxon_id, .rg_id(reg, "Hypsurus caryi"))
  expect_identical(compute_local_occurrence_distance("Embiotoca jacksoni", 34, -119, occ, registry = reg)$n_local_records, 1L)
})

test_that("compute_local_occurrence_distance(registry =): a record with no id is not credited to a called name with no id", {
  .rg_skip(); reg <- .rg_registry()
  # neither "Nonesuch alpha" (called) nor "Nonesuch beta" (recorded) is in the registry; NA must not match NA
  occ <- data.frame(taxon_name = c("Nonesuch beta", "Nonesuch beta", "Embiotoca jacksoni"),
                    decimalLatitude = c(34.0, 34.1, 34.2), decimalLongitude = -119, stringsAsFactors = FALSE)
  d <- compute_local_occurrence_distance(c("Embiotoca jacksoni", "Nonesuch alpha"), 34, -119, occ, registry = reg)
  expect_identical(d$n_local_records[d$taxon_name == "Nonesuch alpha"], 0L)
  expect_true(is.na(d$dist_nearest_km[d$taxon_name == "Nonesuch alpha"]))
  expect_identical(d$n_local_records[d$taxon_name == "Embiotoca jacksoni"], 1L)
  # an unresolved called name still counts the records filed under its own exact name
  d2 <- compute_local_occurrence_distance("Nonesuch beta", 34, -119, occ, registry = reg)
  expect_identical(d2$n_local_records, 2L)
})
