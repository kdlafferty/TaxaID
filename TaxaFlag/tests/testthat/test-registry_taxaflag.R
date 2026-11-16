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

test_that("compute_local_occurrence_distance(registry =): every called name of one taxon gets that taxon's records", {
  .rg_skip(); reg <- .rg_registry()
  occ <- data.frame(taxon_name = c("Embiotoca caryi", "Hypsurus caryi", "Embiotoca jacksoni"),
                    decimalLatitude = c(34.0, 34.1, 34.2), decimalLongitude = -119, stringsAsFactors = FALSE)
  d <- compute_local_occurrence_distance(c("Hypsurus caryi", "Embiotoca caryi", "Embiotoca jacksoni"), 34, -119, occ, registry = reg)
  expect_identical(d$taxon_name, c("Hypsurus caryi", "Embiotoca caryi", "Embiotoca jacksoni"))   # one row per input name, in order
  expect_identical(d$n_local_records, c(2L, 2L, 1L))
  expect_equal(d$dist_nearest_km[1:2], c(0, 0), tolerance = 1e-9)
  expect_identical(d$taxon_id[1], d$taxon_id[2])
})

test_that("compute_local_occurrence_distance(registry = NULL) is unchanged by the registry path", {
  occ <- data.frame(taxon_name = c("A a", "A a", "B b", NA), decimalLatitude = c(34.0, 34.5, 35, 34), decimalLongitude = -119,
                    eventDate = as.Date(c("2020-01-01", "2021-01-01", "2022-01-01", "2023-01-01")), stringsAsFactors = FALSE)
  d <- compute_local_occurrence_distance(c("B b", "A a", "C c", "A a"), 34, -119, occ, date_col = "eventDate")
  expect_snapshot_value(d, style = "serialize")
})
