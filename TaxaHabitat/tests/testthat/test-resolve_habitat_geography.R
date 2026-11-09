# Resolving an unassigned habitat from where the point actually is.
#
# A taxon whose weights span freshwater, estuarine and marine is not uncertain
# about its habitat -- it uses all three -- so over open ocean it is marine.
# The consensus threshold cannot express that because it never sees location.

test_that(".habitat_admissible decides at HABITAT level, not realm level", {
  # The case that motivates the whole function. A gull's candidates are
  # Estuarine | Freshwater | Marine; over open ocean BOTH Estuarine and Marine
  # are "marine realm", so a realm rule finds two matches and gives up -- when
  # the answer is plainly Marine. Estuarine is a transitional coastal habitat.
  cd <- c("Estuarine", "Freshwater", "Marine")
  expect_equal(cd[.habitat_admissible(cd, "ocean")], "Marine")
  # Inland excludes Estuarine as well as Marine: an estuary is a coastal
  # feature, so it is no more admissible 50 km inland than open ocean is.
  # That makes an inland Estuarine|Freshwater|Marine point resolve to
  # Freshwater, which is the desired behaviour and not an accident of the
  # pattern matching.
  expect_equal(cd[.habitat_admissible(cd, "inland")], "Freshwater")
  expect_setequal(cd[.habitat_admissible(cd, "coastal")], cd)
})

test_that(".habitat_admissible excludes marine habitats inland", {
  cd <- c("Marine", "Freshwater", "Terrestrial")
  expect_setequal(cd[.habitat_admissible(cd, "inland")], c("Freshwater", "Terrestrial"))
  expect_equal(cd[.habitat_admissible(cd, "ocean")], "Marine")
})

test_that(".habitat_admissible generalises past one scheme's vocabulary", {
  # Derived from the package's realm patterns, not a hard-coded habitat list.
  expect_true(.habitat_admissible("Rocky Subtidal", "ocean"))
  expect_true(.habitat_admissible("Coastal Pelagic", "ocean"))
  expect_false(.habitat_admissible("Estuarine Mudflat", "ocean"))   # estuarine
  expect_false(.habitat_admissible("Lentic", "ocean"))
  expect_true(.habitat_admissible("Lentic", "inland"))
})

test_that(".habitat_admissible returns FALSE for an unknown zone", {
  expect_false(.habitat_admissible("Marine", "somewhere_else"))
})

test_that("resolve_habitat_by_geography returns input unchanged with no attribute", {
  occ <- data.frame(
    point_id = "p1", decimalLatitude = 34, decimalLongitude = -120,
    main_habitat = NA_character_, stringsAsFactors = FALSE
  )
  r <- suppressMessages(resolve_habitat_by_geography(occ))
  expect_true(is.na(r$main_habitat[1]))
  expect_equal(nrow(r), 1L)
})

test_that("resolve_habitat_by_geography does nothing when nothing is unassigned", {
  occ <- data.frame(
    point_id = "p1", decimalLatitude = 34, decimalLongitude = -120,
    main_habitat = "Marine", stringsAsFactors = FALSE
  )
  attr(occ, "habitat_proportions") <- data.frame(
    point_id = "p1", Marine = 1, Estuarine = 0, stringsAsFactors = FALSE
  )
  r <- suppressMessages(resolve_habitat_by_geography(occ))
  expect_equal(r$main_habitat, "Marine")
  expect_equal(r$habitat_source, "consensus")
})

test_that("resolve_habitat_by_geography validates its inputs", {
  expect_error(resolve_habitat_by_geography("nope"), "dataframe")
  expect_error(
    resolve_habitat_by_geography(data.frame(x = 1)),
    "not found"
  )
})

test_that("a resolved point is marked as geography, not consensus", {
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("rnaturalearthhires")
  skip_if_not_installed("curl")
  # resolve_habitat_by_geography() needs a real NOAA bathymetry fetch
  # (marmap::getNOAA.bathy(), which hits gis.ngdc.noaa.gov) to classify the
  # offshore point's zone. Checked BEFORE the real assertions run, with an
  # explicit skip() reason, rather than wrapping the assertions themselves
  # in `if (!is.na(...))` -- that pattern let this test report PASS having
  # executed zero assertions on its own claim whenever resolution failed for
  # ANY reason (service down, vendored data missing, a future regression),
  # with no visible signal that nothing was actually checked (D5).
  noaa_reachable <- tryCatch({
    h <- curl::new_handle(timeout_ms = 5000L, connecttimeout_ms = 5000L, nobody = TRUE)
    resp <- curl::curl_fetch_memory("https://gis.ngdc.noaa.gov", handle = h)
    resp$status_code < 500
  }, error = function(e) FALSE)
  if (!noaa_reachable) {
    skip(paste(
      "NOAA bathymetry service (gis.ngdc.noaa.gov) is not reachable from this machine --",
      "resolve_habitat_by_geography() cannot classify elevation without it."
    ))
  }

  # Two points: one far offshore (ocean), one already settled by consensus.
  occ <- data.frame(
    point_id = c("sea", "known"),
    decimalLatitude = c(34.0, 34.4),
    decimalLongitude = c(-121.5, -120.0),
    taxon_name = c("gull", "fish"),
    main_habitat = c(NA_character_, "Marine"),
    stringsAsFactors = FALSE
  )
  attr(occ, "habitat_proportions") <- data.frame(
    point_id = c("sea", "known"),
    Marine     = c(0.35, 1),
    Estuarine  = c(0.33, 0),
    Freshwater = c(0.32, 0),
    stringsAsFactors = FALSE
  )
  r <- suppressMessages(resolve_habitat_by_geography(occ))
  expect_equal(r$habitat_source[r$point_id == "known"], "consensus")
  # The offshore point resolves to Marine and is labelled geography. NOAA
  # reachability was already confirmed above, so a resolution failure here
  # is a real regression, not a flaky network -- these assertions always run.
  expect_false(is.na(r$main_habitat[r$point_id == "sea"]))
  expect_equal(r$main_habitat[r$point_id == "sea"], "Marine")
  expect_equal(r$habitat_source[r$point_id == "sea"], "geography")
  # the proportions are NOT rewritten -- the taxon really does use all three
  expect_equal(attr(r, "habitat_proportions")$Estuarine[1], 0.33)
})

test_that("an offshore point resolves to Marine and is labelled geography -- offline", {
  # The companion to the NOAA-backed test above, and the reason it exists: that
  # one probes gis.ngdc.noaa.gov and skips when the service is unreachable, so
  # on an offline machine this package's central claim about geography is
  # never checked at all. The probe is right -- it was added so the test could
  # not report PASS having executed zero assertions -- but a skip is still a
  # gap. This test mocks the layer machinery that does the fetching, so the
  # zone-to-habitat decision always runs.
  #
  # flag_habitat_inconsistencies() is the seam: resolve_habitat_by_geography()
  # delegates the land polygon, coastline and bathymetry work to it and then
  # reads elevation_m and dist_to_coast_km back out. Mocking it supplies that
  # geography directly -- an offshore point 60 km out at -2000 m, and a point
  # already settled by consensus.
  # The mock records that it ran. Without this the test is worthless: if the
  # binding failed to take, the real function would fetch from NOAA and the
  # assertions would still pass on this machine, so a test whose whole purpose
  # is to be offline would quietly be the opposite.
  used <- new.env(parent = emptyenv())
  used$n <- 0L
  fake_geo <- function(x, habitat_col = "main_habitat", ...) {
    used$n <- used$n + 1L
    x$elevation_m <- -2000
    x$dist_to_coast_km <- 60
    x$spatial_flag <- FALSE
    x$spatial_flag_reason <- NA_character_
    x
  }
  # No .env: local_mocked_bindings() defaults to the caller's environment,
  # which inside test_that() IS this test's frame. Passing parent.frame()
  # scoped the mock to a WIDER frame than the test, so it could outlive the
  # block it belongs to. expect_gt(used$n, 0L) below is what makes this
  # testable: if the binding does not take, the real NOAA path runs and the
  # counter stays 0.
  testthat::local_mocked_bindings(
    flag_habitat_inconsistencies = fake_geo
  )

  occ <- data.frame(
    point_id = c("sea", "known"),
    decimalLatitude = c(34.0, 34.4),
    decimalLongitude = c(-121.5, -120.0),
    taxon_name = c("gull", "fish"),
    main_habitat = c(NA_character_, "Marine"),
    stringsAsFactors = FALSE
  )
  attr(occ, "habitat_proportions") <- data.frame(
    point_id = c("sea", "known"),
    Marine     = c(0.35, 1),
    Estuarine  = c(0.33, 0),
    Freshwater = c(0.32, 0),
    stringsAsFactors = FALSE
  )

  r <- suppressMessages(resolve_habitat_by_geography(occ))
  expect_gt(used$n, 0L) # the mock really replaced the fetching path
  # The already-settled point keeps its source; the offshore one is resolved by
  # geography, to the one habitat admissible far out at sea.
  expect_equal(r$habitat_source[r$point_id == "known"], "consensus")
  expect_false(is.na(r$main_habitat[r$point_id == "sea"]))
  expect_equal(r$main_habitat[r$point_id == "sea"], "Marine")
  expect_equal(r$habitat_source[r$point_id == "sea"], "geography")
})
