# flag_habitat_inconsistencies() itself has no offline code path -- every
# real call downloads live Natural Earth polygons and NOAA GEBCO bathymetry
# (confirmed: rnaturalearth::ne_countries()/ne_coastline() and
# marmap::getNOAA.bathy() are both called unconditionally on any valid
# input). That matches this ecosystem's own established precedent for
# genuinely network-bound functions (e.g. TaxaTools::verify_taxon_names()/
# census_genus_species(), "online tests skipped offline"). What IS tested
# here, offline, is the input validation that runs BEFORE any network call
# -- real, reachable failure modes a user can hit with no network at all.

test_that("stops when a required column is missing", {
  occurrence_data <- data.frame(
    decimalLatitude  = 40.8,
    decimalLongitude = -124.2,
    stringsAsFactors = FALSE
  )
  expect_error(
    flag_habitat_inconsistencies(occurrence_data),
    "main_habitat"
  )
})

test_that("stops when lat_col is missing", {
  occurrence_data <- data.frame(
    decimalLongitude = -124.2,
    main_habitat     = "Marine",
    stringsAsFactors = FALSE
  )
  expect_error(
    flag_habitat_inconsistencies(occurrence_data),
    "decimalLatitude"
  )
})

test_that("stops when lon_col is missing", {
  occurrence_data <- data.frame(
    decimalLatitude = 40.8,
    main_habitat    = "Marine",
    stringsAsFactors = FALSE
  )
  expect_error(
    flag_habitat_inconsistencies(occurrence_data),
    "decimalLongitude"
  )
})

test_that("column-existence check reads lat_col/lon_col/habitat_col, not hardcoded defaults", {
  # occurrence_data has a custom-named "hab" column but no "main_habitat" --
  # the error must name "hab" (the value actually supplied via habitat_col),
  # confirming the check is parameterised rather than hardcoded to the
  # default column names.
  occurrence_data <- data.frame(
    lat = 40.8, lon = -124.2,
    stringsAsFactors = FALSE
  )
  expect_error(
    flag_habitat_inconsistencies(
      occurrence_data,
      lat_col = "lat", lon_col = "lon", habitat_col = "hab"
    ),
    "Column 'hab' not found",
    fixed = TRUE
  )
})
